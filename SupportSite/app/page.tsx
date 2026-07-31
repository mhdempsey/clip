export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="wordmark" href="#top" aria-label="Clip home">
          clip
        </a>
        <nav aria-label="Main navigation">
          <a href="#how-it-works">How it works</a>
          <a href="#privacy">Privacy</a>
          <a href="#support">Support</a>
        </nav>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">Listen. Read. Keep the good parts.</p>
          <h1>Your audiobook and ebook, in the same place.</h1>
          <p className="lede">
            Drop a DRM-free ebook and audiobook into Clip for Mac. Clip lines
            them up and sends the synced book to your iPhone for seamless
            listening and reading.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="#how-it-works">
              See how Clip works
            </a>
            <a className="button quiet" href="#support">
              Get help
            </a>
          </div>
        </div>

        <div className="clip-card" aria-label="A sample Clip highlight">
          <div className="clip-card-top">
            <span>12:42</span>
            <span className="now-playing">Now listening</span>
          </div>
          <blockquote>
            “The sentence you want to remember is already waiting for you.”
          </blockquote>
          <div className="wave" aria-hidden="true">
            <span />
            <span />
            <span />
            <span />
            <span />
            <span />
            <span />
            <span />
            <span />
          </div>
          <div className="clip-action">
            <span className="scribble-circle">clip</span>
            <p>
              Tap the button or say <strong>“Clip that.”</strong>
            </p>
          </div>
        </div>
      </section>

      <section className="section" id="how-it-works">
        <div className="section-heading">
          <p className="eyebrow">A three-step ritual</p>
          <h2>From Mac to a highlight you’ll actually revisit.</h2>
        </div>

        <ol className="steps">
          <li>
            <span className="step-number">1</span>
            <h3>Pair your book</h3>
            <p>
              Open Clip on your Mac, then drop in a DRM-free EPUB and its
              matching audiobook. Clip aligns the words with the audio.
            </p>
          </li>
          <li>
            <span className="step-number">2</span>
            <h3>Listen or read on iPhone</h3>
            <p>
              Your synced book arrives through your private iCloud Drive
              container. Switch between the player and reader without losing
              your place.
            </p>
          </li>
          <li>
            <span className="step-number">3</span>
            <h3>Clip the passage</h3>
            <p>
              While listening, tap <em>Clip</em> or say “Clip that.” Clip sends
              the matching passage to Readwise, where it can flow into
              Marginalia with the rest of your highlights.
            </p>
          </li>
        </ol>

        <aside className="note">
          <span aria-hidden="true">↳</span>
          <p>
            Clip is an independent app and is not affiliated with Readwise or
            Marginalia. A Readwise account is required to export highlights.
          </p>
        </aside>
      </section>

      <section className="section privacy" id="privacy">
        <div className="section-heading">
          <p className="eyebrow">Privacy policy</p>
          <h2>Your books stay yours.</h2>
          <p className="effective">Effective July 19, 2026</p>
        </div>

        <div className="policy-grid">
          <article>
            <h3>What Clip stores</h3>
            <p>
              Clip stores your imported books, audio, alignment data, playback
              position, and app settings on your devices and in Clip’s private
              iCloud Drive container. Clip does not operate an account system,
              advertising network, or analytics service.
            </p>
          </article>
          <article>
            <h3>What leaves the app</h3>
            <p>
              When you choose to export a highlight, Clip sends the selected
              passage and its book details to Readwise using the Readwise API.
              Your Readwise access token is stored in Apple Keychain and is
              sent only to Readwise.
            </p>
          </article>
          <article>
            <h3>Third-party services</h3>
            <p>
              Apple processes data used by iCloud under Apple’s privacy policy.
              Readwise processes exported highlights under Readwise’s privacy
              policy. Marginalia receives highlights only through a connection
              you set up with your Readwise account; Clip does not send data to
              Marginalia directly.
            </p>
            <p className="policy-links">
              <a href="https://www.apple.com/legal/privacy/" rel="noreferrer">
                Apple privacy
              </a>
              <a href="https://readwise.io/privacy" rel="noreferrer">
                Readwise privacy
              </a>
            </p>
          </article>
          <article>
            <h3>Your choices</h3>
            <p>
              You can remove books from Clip, delete Clip’s files from iCloud
              Drive, remove your Readwise token in Clip, or revoke the token in
              Readwise. To delete highlights already exported, use your
              Readwise account controls.
            </p>
          </article>
          <article>
            <h3>Children and changes</h3>
            <p>
              Clip is not directed to children under 13. If this policy changes,
              the updated policy and effective date will be posted here.
            </p>
          </article>
          <article>
            <h3>Questions</h3>
            <p>
              For privacy questions, email{" "}
              <a href="mailto:mdemps9190@hotmail.com">
                mdemps9190@hotmail.com
              </a>
              .
            </p>
          </article>
        </div>
      </section>

      <section className="section support" id="support">
        <div>
          <p className="eyebrow">Support</p>
          <h2>Stuck on a chapter?</h2>
          <p className="support-copy">
            Tell us which device you’re using, what you expected, and what
            happened. Please don’t include your audiobook, ebook, or Readwise
            token.
          </p>
          <a
            className="button primary"
            href="mailto:mdemps9190@hotmail.com?subject=Clip%20support"
          >
            Email Clip support
          </a>
        </div>
        <div className="faq">
          <details>
            <summary>What books can I use?</summary>
            <p>
              Use a DRM-free EPUB and audiobook that you have the right to use.
              Clip does not remove DRM or provide book files.
            </p>
          </details>
          <details>
            <summary>Why is the first Mac sync taking a while?</summary>
            <p>
              The first alignment downloads an on-device speech model. Long
              books also take time to align. Keep Clip open until the book is
              ready.
            </p>
          </details>
          <details>
            <summary>Why isn’t my highlight in Readwise?</summary>
            <p>
              Check your Readwise token in Clip’s settings and confirm you’re
              online. Pending highlights are retried automatically.
            </p>
          </details>
          <details>
            <summary>Is there a demo book?</summary>
            <p>
              Yes.{" "}
              <a href="/Clip-Demo.clipbook.zip" download>
                Download Clip’s original 23-second demo
              </a>
              , expand the ZIP in Files, then open the resulting{" "}
              <code>Clip-Demo.clipbook</code> package in Clip.
            </p>
          </details>
        </div>
      </section>

      <footer>
        <a className="wordmark footer-mark" href="#top">
          clip
        </a>
        <p>Made for readers with their hands full.</p>
        <div>
          <a href="#privacy">Privacy</a>
          <a href="#support">Support</a>
        </div>
      </footer>
    </main>
  );
}
