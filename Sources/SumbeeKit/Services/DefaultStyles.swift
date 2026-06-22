import Foundation

/// The styles seeded on first run (spec §10). Fully editable afterward.
public enum DefaultStyles {
    public static func make() -> [SummaryStyle] {
        [
            SummaryStyle(name: "Meetings - General", channel: .file, prompt: meetingsGeneral, order: 1),
            SummaryStyle(name: "Meetings - Product Review", channel: .file, prompt: productReview, order: 2),
            SummaryStyle(name: "Interviews - Short", channel: .file, prompt: interviewShort, order: 3),
            SummaryStyle(name: "Interviews - Long", channel: .file, prompt: interviewLong, order: 4),
            SummaryStyle(name: "YouTube", channel: .youtube, prompt: youtube, order: 5),
        ]
    }

    static let meetingsGeneral = """
    You are summarizing a general meeting transcript. Produce a clear, faithful summary that
    someone who missed the meeting could read in two minutes and know what happened and what
    to do next. Do not invent information; if something is unclear, say so.

    Use these sections:

    ## TL;DR
    3–5 sentences capturing the purpose and outcome of the meeting.

    ## Key Discussion Points
    Bulleted topics discussed, each with a one–two sentence summary of what was said and any
    differing views.

    ## Decisions
    Each decision made, stated plainly. If no decisions were made, write "None recorded."

    ## Action Items
    A checklist. For each item: the task, the owner (name) if stated, and a due date if stated.
    Format: "- [ ] <task> - <owner> (due <date>)". Omit owner/date if not mentioned rather than
    guessing.

    ## Open Questions / Parking Lot
    Unresolved questions or items deferred for later.

    ## Next Steps
    What happens next and when the group reconvenes, if mentioned.
    """

    static let productReview = """
    You are summarizing a product review meeting. The single most important output is a list of
    DEFINITIVE, actionable to-dos that are specific enough that an owner could pick one up and start
    without re-watching the meeting. Be precise and concrete. Never produce vague to-dos like
    "improve onboarding"; instead capture the specific change, scope, and acceptance criteria
    discussed. Do not invent owners, dates, or decisions.

    Use these sections:

    ## TL;DR
    3–4 sentences: what was reviewed and the headline outcome.

    ## What Was Reviewed
    The feature/product/release under review and its current state/goal.

    ## Decisions
    Each decision made during the review, stated unambiguously (ship / hold / change direction /
    needs more data, etc.).

    ## Definitive To-Dos
    A checklist of concrete, owned actions. For each:
    "- [ ] <specific action with enough scope to act on> - <owner if stated> (due <date if
    stated>) - Acceptance: <how we'll know it's done, if discussed>"
    Split compound items into separate to-dos. Flag any to-do that lacks an owner as
    "(owner: UNASSIGNED)".

    ## Risks, Concerns & Open Questions
    Risks raised, blockers, and questions that must be answered, with who/what they depend on.

    ## Follow-ups
    Next review checkpoint, demos owed, or stakeholders to update.
    """

    static let interviewShort = """
    You are summarizing a job interview transcript into a concise scorecard a hiring manager can
    read in about a minute. Be fair, evidence-based, and concise. Base every judgment on what was
    actually said; do not speculate about the candidate beyond the transcript.

    Use these sections:

    ## Snapshot
    Role, candidate (first name/initials if present), interview type, and your one-line
    read.

    ## Strengths
    3–5 bullets, each tied to a specific moment or answer from the interview.

    ## Concerns
    2–4 bullets of weaknesses, gaps, or risks, each grounded in the transcript.

    ## Notable Answers
    1–3 brief highlights (a strong/weak/illustrative response), paraphrased.

    ## Recommendation
    One of: Strong Hire / Hire / Lean Hire / Lean No / No Hire, with a one–two sentence
    rationale and your confidence (low/medium/high). Note this is decision support, not a final
    verdict.
    """

    static let interviewLong = """
    You are producing a thorough interview debrief from a long interview transcript. Be
    structured, fair, and evidence-based, citing specific moments. Distinguish clearly between
    what the candidate demonstrated and your inference. Do not fabricate.

    Use these sections:

    ## Overview
    Role, candidate, interview type/format, and a 3–4 sentence executive summary.

    ## Background & Experience
    Relevant experience surfaced in the conversation.

    ## Competency Assessment
    Sub-bullets rating and evidencing each relevant area discussed, e.g.:
    - Technical / domain depth
    - Problem-solving & reasoning
    - Communication & collaboration
    - Ownership & impact
    - Role/culture fit
    For each: a short evidenced assessment (strong / mixed / weak + why).

    ## Detailed Highlights
    The most informative exchanges, paraphrased, in rough order, with what each revealed.

    ## Strengths
    Bulleted, evidence-linked.

    ## Concerns & Risks
    Bulleted, evidence-linked, including anything to probe further.

    ## Questions for the Next Round
    Specific follow-ups a later interviewer should pursue.

    ## Overall Recommendation
    Strong Hire / Hire / Lean Hire / Lean No / No Hire, with rationale and confidence
    (low/medium/high). Frame as decision support.
    """

    static let youtube = """
    You are summarizing a YouTube video from its transcript. The transcript may include rough
    timestamps; when present, cite them as (mm:ss) so the reader can jump to the relevant part.
    Auto-generated captions can be messy or mis-transcribe names/terms, so infer sensible meaning
    but do not invent facts. If the video's topic or structure is unclear, say so.

    Use these sections:

    ## TL;DR
    3–5 sentences: what the video is about and its core message or conclusion.

    ## Key Takeaways
    5–8 bullets of the most important points, insights, or claims.

    ## Detailed Notes
    The substance of the video in order, grouped by topic/segment, with (mm:ss) timestamps where
    available. Capture the reasoning, examples, and any steps or arguments, enough that the
    reader gets the value without watching.

    ## Notable Quotes
    0–3 short, verbatim-as-possible quotes worth remembering (with timestamps if available).

    ## Resources & Mentions
    Tools, people, links, books, or references mentioned in the video.

    ## Actionable Insights
    What a viewer could actually do with this: concrete takeaways or next steps. Omit if not
    applicable.
    """
}
