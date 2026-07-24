import SwiftUI

// The app's governing legal documents, rendered by LegalDocumentView and accepted at
// onboarding (acceptance is versioned via Disclaimer.currentVersion — bump it whenever
// this copy materially changes so existing users re-consent).
//
// Drafting posture (reviewed 2026-07): current practices are stated as current (local-only,
// nothing transmitted), future capabilities (analytics, sync, backend) are stated as
// conditional-on-launch — never as present practice. HealthKit data is carved out of
// analytics/improvement/sharing uses per App Review 5.1.3. Liability for personal injury
// is NOT nominally excluded (void in many jurisdictions); it is capped only where lawful.
//
// BEFORE SUBMISSION, WITH COUNSEL: confirm the legal entity name and registered address,
// the arbitration provider election (AAA consumer rules below), and the Delaware venue.

struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

enum LegalDocuments {
    static let effectiveDate = "July 21, 2026"
    // No legal entity, contact email, or person is referenced yet (none exists pre-launch,
    // per founder). Before App Store submission: substitute the registered legal entity,
    // add a real contact channel, and have counsel review. "PinWise" stands in as the party.
    static let entityName = "PinWise"
    /// The only contact mechanism the documents reference until a business/email exists.
    static let contactChannel = "the support contact listed on the app's App Store page"

    // MARK: - Terms of Service

    static let terms: [LegalSection] = [
        LegalSection(heading: "1. Acceptance of These Terms", body: """
        These Terms of Service (the "Terms") constitute a legally binding agreement between you \
        and the developer of the PinWise application ("PinWise," \
        "we," "us," or "our"), governing your access to and use of the PinWise application, \
        including all related features, content, and services (collectively, the "Service"). \
        You accept these Terms through the in-app acceptance flow presented before first use \
        and again whenever the Terms materially change. If you do not agree to these Terms, \
        you must not access or use the Service. The Privacy Policy is incorporated into these \
        Terms by reference.
        """),

        LegalSection(heading: "2. Eligibility", body: """
        The Service is available only to individuals who are at least eighteen (18) years of \
        age. By using the Service you represent and warrant that you are at least 18 years old \
        and have the legal capacity to enter into these Terms. The Service is not directed to, \
        and we do not knowingly collect information from, persons under the age of 18.
        """),

        LegalSection(heading: "3. Nature of the Service; No Medical Advice; No Clinician Relationship; Not for Emergencies", body: """
        PinWise is a personal record-keeping, organization, and general-wellness tool. THE \
        SERVICE IS NOT A MEDICAL DEVICE AND IS NOT INTENDED TO DIAGNOSE, TREAT, CURE, MITIGATE, \
        OR PREVENT ANY DISEASE OR CONDITION. Nothing contained in or produced by the Service — \
        including calculators, reference information, evidence tiers, news summaries, reminders, \
        assistant responses, charts, or any other output — constitutes medical advice, a dosing \
        recommendation, or a professional opinion of any kind. No physician–patient, \
        pharmacist–patient, or other clinical or fiduciary relationship is created by your use \
        of the Service. All calculations are arithmetic performed on values you supply and must \
        be independently verified before any reliance. The optional assistant feature is \
        generative AI software; to produce a response it transmits your questions and a snapshot \
        of the data you have entered in the app — and, only if you turn on Apple Health sharing, the \
        Apple Health metrics the app reads — to third-party providers for cloud processing (see \
        the Privacy Policy). Its responses may be inaccurate or incomplete and must not be relied \
        upon. THE SERVICE IS NOT DESIGNED FOR EMERGENCIES — \
        if you believe you are experiencing a medical emergency, call your local emergency \
        number immediately. You are solely responsible for all decisions concerning your \
        health, and you should consult a licensed healthcare professional before starting, \
        stopping, or modifying any regimen, substance, or dose.
        """),

        LegalSection(heading: "4. Regulatory Status of Substances; Research Compounds", body: """
        Certain substances referenced within the Service are not approved by the U.S. Food and \
        Drug Administration or any other regulatory authority for human use, are available only \
        as compounded preparations, or are marketed solely for laboratory research. The \
        inclusion of any substance within the Service's reference library is strictly \
        informational and does not constitute an endorsement, recommendation, or representation \
        of safety, efficacy, legality, or fitness for any purpose. You are solely responsible \
        for ensuring that your acquisition, possession, and use of any substance complies with \
        all laws, regulations, and rules applicable to you, including anti-doping rules where \
        relevant. PinWise does not sell, supply, prescribe, or facilitate the acquisition of \
        any substance.
        """),

        LegalSection(heading: "5. Assumption of Risk", body: """
        The self-administration of any substance, including compounded or research substances, \
        carries inherent and potentially serious risks. TO THE MAXIMUM EXTENT PERMITTED BY \
        APPLICABLE LAW, YOU KNOWINGLY AND VOLUNTARILY ASSUME ALL RISKS ARISING FROM OR RELATING \
        TO YOUR HEALTH DECISIONS AND ANY ACTIONS YOU TAKE OR REFRAIN FROM TAKING IN CONNECTION \
        WITH INFORMATION ENTERED INTO, STORED IN, CALCULATED BY, OR DISPLAYED BY THE SERVICE. \
        The Service depends on the accuracy and completeness of data you supply; inaccurate \
        entries will produce inaccurate outputs.
        """),

        LegalSection(heading: "6. User Content and User-Added Compounds", body: """
        The Service permits you to record notes, protocols, vials, measurements, photographs, \
        and other materials ("User Content"), and to define compounds that are not part of the \
        verified reference library ("User-Added Compounds"). You retain ownership of your User \
        Content. You grant PinWise a limited, non-exclusive license to process User Content \
        solely to operate and display the Service on your device and, where you enable a \
        synchronization or backup feature, to transmit and store it as you direct. With \
        respect to User-Added Compounds, you acknowledge that PinWise possesses no data \
        regarding, and makes no representation whatsoever concerning, their identity, purity, \
        stability, safety, legality, or handling; that all information associated with a \
        User-Added Compound is supplied entirely by you; and that PinWise expressly disclaims \
        all responsibility and liability arising from or relating to User-Added Compounds. If \
        you send us suggestions or feedback, we may use them without restriction or obligation \
        to you.
        """),

        LegalSection(heading: "7. Accounts and Security", body: """
        Certain features may require an account (for example, Sign in with Apple). You are \
        responsible for maintaining the confidentiality of your device and credentials and for \
        all activity occurring under your account. You agree to notify us promptly of any \
        unauthorized use. We may suspend or terminate access for violation of these Terms.
        """),

        LegalSection(heading: "8. License and Intellectual Property", body: """
        Subject to these Terms, PinWise grants you a personal, limited, non-exclusive, \
        non-transferable, revocable license to use the Service on Apple-branded devices that \
        you own or control, as permitted by the Usage Rules set forth in the Apple Media \
        Services Terms and Conditions. The Service, including its software, design, text, \
        graphics, and compilations (excluding your User Content), is owned by \(entityName) or \
        its licensors and is protected by intellectual property laws. You may not copy, \
        modify, distribute, sell, lease, reverse engineer, or create derivative works of the \
        Service except as permitted by law. You agree to comply with applicable third-party \
        terms of agreement when using the Service (for example, your wireless data agreement).
        """),

        LegalSection(heading: "9. Acceptable Use", body: """
        You agree not to: (a) use the Service for any unlawful purpose; (b) interfere with or \
        disrupt the integrity or performance of the Service; (c) attempt to gain unauthorized \
        access to the Service or its related systems; or (d) misrepresent outputs of the \
        Service as medical advice or as having been reviewed by a healthcare professional.
        """),

        LegalSection(heading: "10. Third-Party Services and Content", body: """
        The Service interoperates with third-party services you elect to connect, including \
        Apple Health, and may display summaries of, and links to, third-party publications and \
        registries. Third-party services are governed by their own terms and privacy policies, \
        and PinWise is not responsible for third-party content, accuracy, or practices. News \
        summaries are provided for general information only and may contain errors; always \
        consult the linked primary source.
        """),

        LegalSection(heading: "11. Disclaimer of Warranties", body: """
        THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE," WITH ALL FAULTS AND WITHOUT \
        WARRANTY OF ANY KIND. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, PINWISE \
        DISCLAIMS ALL WARRANTIES, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING WITHOUT LIMITATION \
        IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, ACCURACY, \
        QUIET ENJOYMENT, AND NON-INFRINGEMENT, AND ANY WARRANTY THAT THE SERVICE WILL BE \
        UNINTERRUPTED, ERROR-FREE, OR FREE OF HARMFUL COMPONENTS, OR THAT ANY CALCULATION, \
        REMINDER, PROJECTION, OR ITEM OF INFORMATION WILL BE ACCURATE, COMPLETE, OR RELIABLE. \
        NO ORAL OR WRITTEN INFORMATION OBTAINED FROM PINWISE SHALL CREATE ANY WARRANTY. Some \
        jurisdictions do not allow the exclusion of implied warranties, so some of the above \
        may not apply to you.
        """),

        LegalSection(heading: "12. Limitation of Liability", body: """
        NOTHING IN THESE TERMS EXCLUDES OR LIMITS ANY LIABILITY THAT CANNOT BE EXCLUDED OR \
        LIMITED UNDER APPLICABLE LAW, INCLUDING LIABILITY FOR DEATH OR PERSONAL INJURY CAUSED \
        BY NEGLIGENCE WHERE SUCH LIABILITY MAY NOT LAWFULLY BE EXCLUDED, OR FOR FRAUD. SUBJECT \
        TO THE FOREGOING, AND TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW: (A) IN NO \
        EVENT SHALL \(entityName), ITS OFFICERS, DIRECTORS, EMPLOYEES, CONTRACTORS, OR AGENTS \
        BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE \
        DAMAGES, OR FOR ANY LOSS OF DATA OR LOSS OF PROFITS, ARISING OUT OF OR RELATING TO THE \
        SERVICE OR THESE TERMS, WHETHER BASED ON WARRANTY, CONTRACT, TORT (INCLUDING \
        NEGLIGENCE), PRODUCT LIABILITY, OR ANY OTHER LEGAL THEORY, AND WHETHER OR NOT PINWISE \
        HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES; AND (B) THE AGGREGATE LIABILITY \
        OF \(entityName) FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THE SERVICE SHALL NOT \
        EXCEED THE GREATER OF (i) THE AMOUNTS YOU PAID TO PINWISE FOR THE SERVICE IN THE \
        TWELVE (12) MONTHS PRECEDING THE CLAIM AND (ii) FIFTY U.S. DOLLARS (US $50). Statutory \
        rights you hold as a consumer remain unaffected.
        """),

        LegalSection(heading: "13. Indemnification", body: """
        You agree to defend, indemnify, and hold harmless \(entityName) and its officers, \
        directors, employees, and agents from and against any claims, liabilities, damages, \
        losses, and expenses, including reasonable attorneys' fees, arising out of or in any \
        way connected with: (a) your access to or use of the Service; (b) your User Content or \
        User-Added Compounds; (c) your violation of these Terms; or (d) your violation of any \
        law or the rights of any third party.
        """),

        LegalSection(heading: "14. Dispute Resolution; Arbitration; Class Action Waiver", body: """
        PLEASE READ THIS SECTION CAREFULLY — IT AFFECTS YOUR LEGAL RIGHTS. Before filing a \
        claim, you agree to first notify us through \(contactChannel), describing the dispute, and \
        to attempt informal resolution for thirty (30) days. Except for disputes that qualify \
        for small-claims court in your county of residence, or claims for injunctive relief \
        for intellectual-property misuse (which may be brought in the state or federal courts \
        located in Delaware), any dispute, claim, or controversy arising out of or relating to \
        these Terms or the Service shall be resolved by binding individual arbitration \
        administered by the American Arbitration Association ("AAA") under its Consumer \
        Arbitration Rules then in effect. The arbitrator, and not any court, has exclusive \
        authority to resolve disputes about the interpretation, applicability, or \
        enforceability of this arbitration agreement. Arbitration fees are allocated as \
        provided in the AAA Consumer Arbitration Rules; we will pay filing and arbitrator \
        fees the Rules assign to us. YOU AND PINWISE EACH WAIVE THE RIGHT TO A TRIAL BY JURY \
        AND TO PARTICIPATE IN A CLASS ACTION, CLASS ARBITRATION, OR REPRESENTATIVE PROCEEDING. \
        If the class action waiver is found unenforceable as to a particular claim, that claim \
        (and only that claim) shall proceed in court, and the waiver shall remain enforceable \
        as to all other claims. You may opt out of this arbitration agreement by submitting \
        written notice through \(contactChannel) within thirty (30) days of first accepting \
        these Terms, stating that you decline arbitration. These Terms are governed by the laws of \
        the State of Delaware, USA, without regard to conflict-of-law principles, except where \
        the mandatory consumer-protection law of your place of residence applies.
        """),

        LegalSection(heading: "15. Apple App Store Terms", body: """
        These Terms are concluded between you and \(entityName), not with Apple Inc. \
        ("Apple"). \(entityName), not Apple, is solely responsible for the Service and its \
        content, for furnishing any maintenance and support, and for addressing any claim by \
        you or a third party relating to the Service, including: (i) product-liability \
        claims; (ii) claims that the Service fails to conform to legal or regulatory \
        requirements; (iii) consumer-protection, privacy, or similar claims; and (iv) claims \
        that the Service infringes a third party's intellectual-property rights, including \
        their investigation, defense, settlement, and discharge. In the event of any failure \
        of the Service to conform to an applicable warranty, you may notify Apple, and Apple \
        will refund any purchase price paid for the Service; to the maximum extent permitted \
        by law, Apple has no other warranty obligation with respect to the Service. Apple and \
        its subsidiaries are third-party beneficiaries of these Terms and may enforce them \
        against you. You represent that you are not located in a country subject to a U.S. \
        Government embargo or designated a "terrorist supporting" country, and that you are \
        not on any U.S. Government restricted-party list.
        """),

        LegalSection(heading: "16. Changes, Suspension, and Termination", body: """
        We may modify these Terms from time to time. Material changes will be presented in the \
        app and require your renewed acceptance before continued use. We may modify, suspend, \
        or discontinue the Service, in whole or in part, at any time. You may stop using the \
        Service at any time; deleting the app removes locally stored data from the device \
        (subject to device backups you control). Sections that by their nature should survive \
        termination (including Sections 5, 6, and 11–14) survive.
        """),

        LegalSection(heading: "17. Miscellaneous; Notices; Contact", body: """
        If any provision of these Terms is held unenforceable, it shall be modified to the \
        minimum extent necessary and the remainder shall continue in full force. These Terms, \
        together with the Privacy Policy, constitute the entire agreement between you and \
        \(entityName) regarding the Service and supersede all prior agreements. Our failure \
        to enforce any right is not a waiver. You may not assign these Terms; we may assign \
        them in connection with a merger, acquisition, or sale of assets. We may provide \
        notices to you within the app; you may provide notice to us, and direct questions \
        and complaints, through \(contactChannel).
        """)
    ]

    // MARK: - Privacy Policy

    static let privacy: [LegalSection] = [
        LegalSection(heading: "1. Scope; Controller; Consent", body: """
        This Privacy Policy describes how the developer of the PinWise application ("PinWise," \
        "we," "us" — the data controller where that concept applies) collects, uses, discloses, \
        and safeguards information in connection with the PinWise application. It is \
        incorporated into and forms part of the Terms of Service. This Policy also serves as \
        our consumer health data privacy policy for purposes of the Washington My Health My \
        Data Act and similar state laws. Where processing is based on consent — including for \
        health-related data — that consent is collected through the app's explicit acceptance \
        flow and specific permission prompts (such as the Apple Health authorization sheet), \
        and you may withdraw it at any time as described in Section 8.
        """),

        LegalSection(heading: "2. Information We Collect", body: """
        (a) Information you provide: dose logs, protocols, vial and inventory details, \
        laboratory values and body metrics, symptom entries, notes, User-Added Compounds, an \
        optional profile name and photograph, and support communications. Much of this is \
        consumer health data / sensitive personal information under applicable law. \
        (b) Account information: if you use Sign in with Apple, we receive the identifier \
        and, at your election, the name and email address Apple provides. (c) Apple Health \
        data: with your explicit permission granted through the Health authorization sheet, \
        the app READS the categories shown in that sheet (such as weight, heart-rate metrics, \
        sleep, and steps); the app does not write to Apple Health. (d) Account and AI-usage \
        data: if you create an account, we store your account identifier and a per-day count of \
        assistant messages with our cloud provider to operate sign-in and enforce usage limits. \
        (e) Assistant inputs: when you use the optional cloud assistant, we transmit your \
        questions and a snapshot of the data you entered in the app — and, only if you turn on \
        "Share Apple Health with Natt" (off by default), the Apple Health metrics the app reads — \
        for processing, as described in Section 3. (f) Usage and diagnostic data: THE APP INTEGRATES NO ANALYTICS OR \
        CRASH-REPORTING SERVICE AND TRANSMITS NO GENERAL USAGE OR TELEMETRY DATA beyond the \
        account and assistant data in (d)–(e). If a future update introduces analytics or \
        diagnostics, we will describe them here before they take effect, they will be limited to \
        feature-usage events and technical logs, and they will never include your health \
        records or Apple Health data.
        """),

        LegalSection(heading: "3. How We Use Information", body: """
        We use information to: (a) provide, operate, and maintain the Service on your device; \
        (b) personalize and tailor the experience to you, including remembering preferences, \
        adapting displays, and surfacing relevant features — this personalization happens on \
        your device; (c) provide reminders and notifications you enable; (d) if analytics are \
        introduced in a future update, measure usage and improve the Service using aggregated \
        or de-identified usage information — never your health records — to evaluate and \
        refine features and plan app updates; (e) detect, prevent, and address technical \
        issues, fraud, and abuse; and (f) comply with legal obligations. The optional assistant \
        feature is cloud-based: when you use it, your questions and a bounded snapshot of the data \
        you have entered in the app (such as your protocols, dose logs, symptoms, and lab/body \
        values) are transmitted over an encrypted connection to our cloud infrastructure provider \
        and to a third-party AI model provider — each acting as our processor under confidentiality \
        and data-protection obligations — solely to generate the response shown to you. We instruct \
        these providers not to use your data to train or improve their models and to retain it only \
        transiently as needed to process your request. BY DEFAULT, YOUR APPLE HEALTH DATA IS NOT \
        INCLUDED IN WHAT IS SENT TO THE ASSISTANT; it remains on your device. Only if you turn on \
        "Share Apple Health with Natt" (Settings — Security & Privacy; off by default) are the Apple \
        Health metrics the app reads (weight, resting heart rate, HRV, sleep, and steps) then \
        included in that snapshot, under the same processor confidentiality, no-training, and \
        transient-retention terms above and solely to generate your response; you can turn it off at \
        any time. Legal bases where the GDPR applies: your explicit consent \
        (Articles 6(1)(a) and 9(2)(a)) for health-related data and optional features; \
        performance of our contract with you (Article 6(1)(b)) for operating the Service; and \
        our legitimate interests (Article 6(1)(f)) in securing and debugging the Service. \
        APPLE HEALTH DATA IS USED SOLELY TO PROVIDE THE HEALTH FEATURES YOU HAVE ENABLED, \
        consistent with Apple's developer requirements, and is never used for advertising or \
        marketing, never used to train or improve models or algorithms, never sold, and never \
        shared with third parties for their own purposes.
        """),

        LegalSection(heading: "4. How Information May Be Shared", body: """
        We do not sell your personal information, and we do not share it for cross-context \
        behavioral advertising. Information may be disclosed only: (a) across your own Apple \
        devices, if and when a synchronization or backup feature ships and you enable it — \
        your data would be transmitted to and stored with the provider you choose (for \
        example, your personal iCloud account) so the Service can offer a consistent \
        experience on your devices; (b) to service providers/processors acting on our behalf \
        under contractual confidentiality and data-protection obligations — currently Apple \
        (authentication and, where you enable it, device backup), our cloud infrastructure and \
        authentication provider (which hosts your account identifier and AI-usage counts and \
        relays assistant requests), and a third-party AI model provider (which processes assistant \
        requests to generate responses); these providers are instructed not to use your data for \
        their own purposes or to train their models, and any future provider will be bound by the \
        same obligations; \
        (c) in aggregated or de-identified form that cannot reasonably be used to identify \
        you, for product improvement and analytics, and only if such data is collected under \
        Section 2(d); (d) to comply with law, regulation, legal process, or enforceable \
        governmental request, or to protect the rights, property, or safety of PinWise, our \
        users, or the public; and (e) in connection with a merger, acquisition, financing, or \
        sale of assets, subject to this Policy. Apple Health data is never shared under \
        subsections (c) or (e) and is disclosed only as required to provide the features you \
        enabled or as required by law.
        """),

        LegalSection(heading: "5. Where Your Data Lives", body: """
        Your records are created and stored on your device. Two things are transmitted off-device: \
        (a) if you create an account, your account identifier and per-day assistant-usage counts \
        are stored with our cloud provider to operate sign-in and enforce usage limits; and (b) \
        when you use the optional cloud assistant, the questions and data snapshot described in \
        Section 3 are transmitted to our providers to generate a response and are not retained by \
        them beyond processing your request. Everything else — your full dose, protocol, inventory, \
        symptom, and lab history — remains on your device and in any device backup you choose to \
        enable, and your Apple Health data is not transmitted off your device by the assistant. \
        Additional off-device features (such as cross-device sync or backup) remain disabled until \
        you enable them, and this Policy will be updated before any such feature launches.
        """),

        LegalSection(heading: "6. Retention and Deletion", body: """
        Records you create are retained on your device until you delete them or delete the \
        app. Account identifiers are retained while your account is active and deleted when \
        you delete your account. You may delete individual records in the app, remove your \
        profile photograph, sign out, or delete the app entirely. If we hold data off-device \
        in the future, we will retain it only as long as necessary for the purposes described \
        in this Policy or as required by law.
        """),

        LegalSection(heading: "7. Security", body: """
        We employ administrative, technical, and organizational measures appropriate to the \
        nature of the data, including reliance on the operating system's sandboxing and \
        encryption-at-rest for on-device storage. No method of transmission or storage is \
        completely secure, and we cannot guarantee absolute security.
        """),

        LegalSection(heading: "8. Your Rights", body: """
        Depending on your jurisdiction — including under the EU/UK General Data Protection \
        Regulation, the California Consumer Privacy Act as amended by the CPRA, the \
        Washington My Health My Data Act, and similar laws — you may have rights to know or \
        access, correct, delete, or receive a portable copy of your personal information \
        (including consumer health data); to limit the use of sensitive personal information; \
        to withdraw consent at any time; to restrict or object to certain processing; and to \
        lodge a complaint with a supervisory authority. We do not sell or share personal \
        information as those terms are defined by the CCPA, and we honor these rights without \
        discrimination. Because your records live on your device, most rights can be \
        exercised directly in the app (view, correct, delete, export); for anything else — \
        including requests made through an authorized agent — submit a request through \
        \(contactChannel) and we will verify and respond within the period required by applicable law. Our app \
        does not respond to browser "Do Not Track" signals because it is not a website and \
        does not track you across sites or apps; if we ever engage in "sharing" under the \
        CPRA, we will honor the Global Privacy Control.
        """),

        LegalSection(heading: "9. Children", body: """
        The Service is not directed to individuals under 18, and we do not knowingly collect \
        personal information from them. If we learn that we have collected personal \
        information from a person under 18, we will delete it.
        """),

        LegalSection(heading: "10. International Transfers", body: """
        The cloud assistant and account features may process your data in a country other than \
        your own. Where required, we rely on safeguards recognized by applicable law (such as \
        standard contractual clauses) for these transfers, and we will update this Policy if our \
        providers or transfer mechanisms change.
        """),

        LegalSection(heading: "11. Changes to This Policy; Contact", body: """
        We may update this Policy from time to time. Material changes will be presented in \
        the app for renewed acceptance before they take effect. The effective date above \
        reflects the latest revision. Questions, concerns, or rights requests may be \
        submitted through \(contactChannel).
        """)
    ]
}

/// Renders the Terms of Service and Privacy Policy as a segmented, scrollable document.
/// Presented from the welcome screen, onboarding, and About & Legal.
struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var doc: Doc = .terms
    enum Doc: Hashable { case terms, privacy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Picker("", selection: $doc) {
                        Text("Terms of Service").tag(Doc.terms)
                        Text("Privacy Policy").tag(Doc.privacy)
                    }
                    .pickerStyle(.segmented)

                    Text("Effective \(LegalDocuments.effectiveDate)")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)

                    ForEach(doc == .terms ? LegalDocuments.terms : LegalDocuments.privacy) { section in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(section.heading)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrandColor.textPrimary)
                            Text(section.body)
                                .font(.footnote)
                                .foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                }
                .padding(Space.lg)
            }
            .background(BrandColor.background.ignoresSafeArea())
            .navigationTitle("Terms & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
