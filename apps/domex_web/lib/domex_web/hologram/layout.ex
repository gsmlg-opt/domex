defmodule DomexWeb.Hologram.Layout do
  use Hologram.Component

  alias Hologram.UI.Runtime

  @impl true
  def init(_props, component, _server) do
    stylesheet =
      DuskmoonBundler.static_path(DomexWeb.Endpoint, "/assets/css/app.css",
        profile: :domex_web,
        outdir: "priv/static/assets"
      )

    put_state(component, :stylesheet, stylesheet)
  end

  @impl true
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en" data-theme="moonlight" class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Hub overview · Domex</title>
        <link rel="icon" type="image/svg+xml" href="/images/logo.svg" />
        <link rel="stylesheet" href={@stylesheet} />
        <Runtime />
      </head>
      <body class="min-h-full antialiased bg-surface text-on-surface">
        <header class="border-b border-outline-variant bg-surface-container">
          <nav class="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-5 sm:px-6 lg:px-8" aria-label="Main navigation">
            <a id="hologram-brand" href="/" class="flex items-center gap-3 font-bold tracking-tight transition-opacity hover:opacity-80">
              <img src="/images/logo.svg" alt="" class="size-8" />
              <span class="text-xl">Domex</span>
              <span class="rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary">Local hub</span>
            </a>
            <a id="hologram-dashboard-link" href="/" class="rounded-lg px-4 py-2 text-sm font-semibold text-on-surface-variant transition-colors hover:bg-surface-container-high hover:text-on-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
              Device controls →
            </a>
          </nav>
        </header>
        <main id="hologram-main" class="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
          <slot />
        </main>
      </body>
    </html>
    """
  end
end
