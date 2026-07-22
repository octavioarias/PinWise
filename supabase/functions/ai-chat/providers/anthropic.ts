// Anthropic Claude adapter. Calls the Messages API with streaming and re-yields provider-neutral
// ChatEvents. Reads model + key from env so nothing is hard-coded:
//   ANTHROPIC_API_KEY (required), AI_MODEL (optional, defaults to a current Sonnet).
import type { ChatEvent, ChatProvider, ChatRequest } from "./types.ts";

const API_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";
// Decision (deep-research, 2026-07): Haiku 4.5 is the pick — wins the health-data privacy
// criterion, ~$1/$5 per M tokens, trivial cost at PinWise's volume. Runner-up: claude-sonnet-4-6
// (same adapter/API, ~3x cost) if refusal-robustness or extraction accuracy needs it. Verify the
// exact model id against Anthropic's live catalog at deploy time; override with AI_MODEL.
const DEFAULT_MODEL = "claude-haiku-4-5";

export class AnthropicProvider implements ChatProvider {
  readonly name = "anthropic";
  private readonly apiKey: string;
  private readonly model: string;

  constructor() {
    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) throw new Error("ANTHROPIC_API_KEY is not set");
    this.apiKey = key;
    this.model = Deno.env.get("AI_MODEL") ?? DEFAULT_MODEL;
  }

  async *stream(req: ChatRequest): AsyncGenerator<ChatEvent> {
    // Prompt caching: mark the stable prefix so Anthropic reuses it at ~0.1x input cost instead of
    // re-charging full price for the guardrails + user context on every turn. Two breakpoints:
    //  1. guardrails — identical for every user, so it caches across the whole user base;
    //  2. guardrails+context — stable across the turns of one conversation, so follow-up messages
    //     in a session read it from cache.
    // Caching only activates above Anthropic's minimum cacheable length; below it these markers are
    // harmless no-ops. This is the main cost lever — it lets us run a stronger model for the same
    // spend. Prompt caching is GA for current models, so no beta header is needed.
    const systemBlocks: Array<Record<string, unknown>> = [
      { type: "text", text: req.system, cache_control: { type: "ephemeral" } },
    ];
    if (req.context && req.context.trim()) {
      systemBlocks.push({ type: "text", text: req.context, cache_control: { type: "ephemeral" } });
    }

    const resp = await fetch(API_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": API_VERSION,
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: req.maxTokens ?? 1024,
        system: systemBlocks,
        stream: true,
        messages: req.messages.map((m) => ({ role: m.role, content: m.content })),
      }),
    });

    if (!resp.ok || !resp.body) {
      const detail = await resp.text().catch(() => "");
      throw new Error(`anthropic ${resp.status}: ${detail.slice(0, 500)}`);
    }

    // Anthropic streams Server-Sent Events. We parse the event stream line-by-line and translate
    // the events we care about into ChatEvents. Input tokens arrive on message_start; output tokens
    // accumulate on message_delta.usage.output_tokens.
    let inputTokens = 0;
    let outputTokens = 0;
    const decoder = new TextDecoder();
    let buffer = "";

    const reader = resp.body.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // SSE frames are separated by a blank line; each frame has one or more `field: value` lines.
      let sep: number;
      while ((sep = buffer.indexOf("\n\n")) !== -1) {
        const frame = buffer.slice(0, sep);
        buffer = buffer.slice(sep + 2);

        const dataLine = frame.split("\n").find((l) => l.startsWith("data:"));
        if (!dataLine) continue;
        const json = dataLine.slice(5).trim();
        if (!json || json === "[DONE]") continue;

        let evt: Record<string, unknown>;
        try {
          evt = JSON.parse(json);
        } catch {
          continue;
        }

        switch (evt.type) {
          case "message_start": {
            const usage = (evt.message as Record<string, unknown> | undefined)
              ?.usage as Record<string, number> | undefined;
            if (usage?.input_tokens) inputTokens = usage.input_tokens;
            break;
          }
          case "content_block_delta": {
            const delta = evt.delta as Record<string, string> | undefined;
            if (delta?.type === "text_delta" && delta.text) {
              yield { type: "delta", text: delta.text };
            }
            break;
          }
          case "message_delta": {
            const usage = evt.usage as Record<string, number> | undefined;
            if (usage?.output_tokens) outputTokens = usage.output_tokens;
            break;
          }
        }
      }
    }

    yield { type: "usage", inputTokens, outputTokens };
  }
}
