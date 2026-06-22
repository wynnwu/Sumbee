import Foundation

/// Canonical, viral-marketing-tuned copy for sharing Sumbee. Pure value type (no UI/AppKit) so the
/// exact strings + generated links are unit-testable and reused by every share surface.
///
/// Viral best practices baked in: one clear product (repo) link, a short benefit-led message with a
/// light hook + emoji, a ready-to-post tweet (kept well under platform limits), and platform deep
/// links so a share is one click, not copy-paste-and-figure-it-out.
public enum ShareContent {
    /// The single destination every share points at - the public GitHub repo.
    public static let repoURLString = "https://github.com/wynnwu/Sumbee"
    public static let repoURL = URL(string: repoURLString)!

    /// Short, benefit-led headline used as the share's call to action.
    public static let headline = "Enjoying Sumbee?"

    /// One-line value prop reused as the subject / preview line.
    public static let tagline = "Turn transcripts & YouTube videos into clean notes - on your Mac, no lock-in."

    /// The default message a sharer posts. Short, specific, ends with the link so it survives
    /// truncation on any platform.
    public static let message =
        "I've been using Sumbee to turn transcripts & YouTube videos into clean Markdown notes on my Mac - local-first, your files, no lock-in. Free & open source: \(repoURLString)"

    /// A tweet-sized variant (kept short so the URL + a quote/RT still fit comfortably).
    public static let tweet =
        "Sumbee turns transcripts & YouTube videos into clean notes on your Mac - local-first, no lock-in. Free & open source \(repoURLString)"

    /// Email subject line for the Mail share.
    public static let emailSubject = "You might like Sumbee"

    /// X / Twitter web intent (works without the native app installed).
    public static var twitterShareURL: URL? {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        components?.queryItems = [URLQueryItem(name: "text", value: tweet)]
        return components?.url
    }

    /// A `mailto:` URL with a prefilled subject and body for the "Email a friend" link.
    public static var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: emailSubject),
            URLQueryItem(name: "body", value: message),
        ]
        return components.url
    }
}
