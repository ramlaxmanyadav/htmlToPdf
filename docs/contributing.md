# Contributing & Releasing

[← Back to README](../README.md)

## Running the test suite

```
bundle install
bundle exec rake   # alias for `rake spec`
```

The suite needs a real Chrome or Chromium install for the specs tagged `:chrome` (most of
`spec/htmlToPdf/browser_pool_spec.rb`, and all of `spec/integration/controller_spec.rb`, which
drives a real Rails dispatch via a minimal [combustion](https://github.com/pat/combustion) app
under `spec/internal`) — those specs are automatically excluded with a clear message if
`Ferrum::Browser.new` can't find a binary, so the rest of the suite (the `PrintOptions` and
`Configuration` unit specs, and the stubbed-Ferrum half of `BrowserPool`'s specs) still runs
without one. `spec/integration/controller_spec.rb` also shells out to `pdftotext` (part of
`poppler-utils`) to assert on actual rendered PDF content — install it locally the same way CI
does (`apt-get install poppler-utils` on Debian/Ubuntu, `brew install poppler` on macOS) to run
those checks.

`spec/internal` is the combustion-managed dummy Rails app — only the files this gem's own specs
actually exercise exist there (a couple of controllers, views, and routes), not a full scaffolded
app.

## Extending it

- `lib/htmlToPdf/print_options.rb` is where `pdf_options`/`config.default_options` turn into the
  keyword arguments `Ferrum::Page#pdf` expects — see
  [Architecture](architecture.md#print_options-and-security) before adding a new option, especially
  anything that (like `header_template`) is raw HTML rather than a validated value.
- `lib/htmlToPdf/browser_pool.rb` owns the one pooled `Ferrum::Browser` per process — see
  [Architecture](architecture.md#browserpool) for the context-leak trap the block form of
  `create_page` exists to avoid.
- `lib/htmlToPdf.rb` is the controller-facing `around_action` itself — read
  [Rails integration](rails-integration.md) and the
  ["DoubleRenderError" guide](https://ramlaxmanyadav.github.io/htmlToPdf/rails-double-render-pdf.html)
  before changing its control flow; the bug those describe only shows up against a real Rails
  dispatch, not a stub, which is exactly why `spec/integration/controller_spec.rb` exists.

## Releasing

Two GitHub Actions workflows handle this repo's own CI/CD:

- [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — runs the spec suite, a syntax sweep,
  and a `gem build` sanity check on every push/PR to `master`, across every Ruby version
  `required_ruby_version` claims to support (3.1 through 3.4).
- [`.github/workflows/release.yml`](../.github/workflows/release.yml) — pushing a tag matching `v*`
  re-runs the test suite, then publishes to RubyGems via
  [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (OIDC — no API key stored
  as a GitHub secret, nothing to leak or rotate).

Trusted Publishing needs a one-time setup on rubygems.org before the release workflow can actually
publish anything (this can't be done from the repo itself — it's a rubygems.org account action):
sign in, go to the htmlToPdf gem's page → **Trusted Publishers** → add one with owner
`ramlaxmanyadav`, repository `htmlToPdf`, workflow filename `release.yml`, no environment. After
that, `git tag vX.Y.Z && git push origin vX.Y.Z` is the entire release process — bump
`lib/htmlToPdf/version.rb`, update `CHANGELOG.md`, commit, tag, push the tag, and the workflow does
the rest.
