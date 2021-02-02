defmodule CodeReloader.Plug do
  @moduledoc """
  A plug and module to handle automatic code reloading.

  For each request, the Plug checks and recompiles any of the modules in
  the project using `CodeReloader.Server.reload!/1`.

  ```
  defmodule MyRouter do
    use Plug.Router

    plug CodeReloader.Plug, endpoint: __MODULE__
    
    ...etc...
  end
  ```

  Every request through the router will attempt to kick-off a recomplile
  of the current project, and report failures by rendering an error page
  for the web browser.
  """

  @spec reload!(module) :: {:ok, binary()} | {:error, binary()}
  defdelegate reload!(endpoint), to: CodeReloader.Server

  ## Plug

  @behaviour Plug
  import Plug.Conn
  import Logger

  @style %{
    primary: "#EB532D",
    xx: "0",
    accent: "#a0b0c0",
    text_color: "304050",
    logo:
      "data:image/png;base64,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",
    monospace_font: "menlo, consolas, monospace"
  }

  @doc """
  API used by Plug to start the code reloader.
  """
  def init(opts), do: Keyword.put_new(opts, :reloader, &CodeReloader.Plug.reload!/1)

  @doc """
  API used by Plug to invoke the code reloader on every request.
  """
  def call(conn, opts) do
    reloader = Keyword.get(opts, :reloader)
    endpoint = Keyword.get(opts, :endpoint)
    do_call(conn, reloader, endpoint)
  end

  defp do_call(conn, _reloader, endpoint) when is_nil(endpoint) do
    Logger.error(fn ->
      "CodeReloader: couldn't reload. opts[:endpoint] must be specified when using CodeReloader.Plug."
    end)

    conn
  end

  defp do_call(conn, reloader, endpoint) do
    case reloader.(endpoint) do
      {:ok, _output} ->
        conn

      {:error, output} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(500, template(output))
        |> halt()
    end
  end

  defp template(output) do
    {error, headline} = get_error_details(output)

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>CompileError</title>
        <meta name="viewport" content="width=device-width">
        <style>/*! normalize.css v4.2.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,details,figcaption,figure,footer,header,main,menu,nav,section,summary{display:block}audio,canvas,progress,video{display:inline-block}audio:not([controls]){display:none;height:0}progress{vertical-align:baseline}template,[hidden]{display:none}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}dfn{font-style:italic}h1{font-size:2em;margin:0.67em 0}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-0.25em}sup{top:-0.5em}img{border-style:none}svg:not(:root){overflow:hidden}code,kbd,pre,samp{font-family:monospace, monospace;font-size:1em}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}button,input,optgroup,select,textarea{font:inherit;margin:0}optgroup{font-weight:bold}button,input{overflow:visible}button,select{text-transform:none}button,html [type="button"],[type="reset"],[type="submit"]{-webkit-appearance:button}button::-moz-focus-inner,[type="button"]::-moz-focus-inner,[type="reset"]::-moz-focus-inner,[type="submit"]::-moz-focus-inner{border-style:none;padding:0}button:-moz-focusring,[type="button"]:-moz-focusring,[type="reset"]:-moz-focusring,[type="submit"]:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid #c0c0c0;margin:0 2px;padding:0.35em 0.625em 0.75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}textarea{overflow:auto}[type="checkbox"],[type="radio"]{box-sizing:border-box;padding:0}[type="number"]::-webkit-inner-spin-button,[type="number"]::-webkit-outer-spin-button{height:auto}[type="search"]{-webkit-appearance:textfield;outline-offset:-2px}[type="search"]::-webkit-search-cancel-button,[type="search"]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-input-placeholder{color:inherit;opacity:0.54}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}</style>
        <style>
        html, body, td, input {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", "Fira Sans", "Droid Sans", "Helvetica Neue", sans-serif;
        }

        * {
            box-sizing: border-box;
        }

        html {
            font-size: 15px;
            line-height: 1.6;
            background: #fff;
            color: #{@style.text_color};
        }

        @media (max-width: 768px) {
            html {
                 font-size: 14px;
            }
        }

        @media (max-width: 480px) {
            html {
                 font-size: 13px;
            }
        }

        button:focus,
        summary:focus {
            outline: 0;
        }

        summary {
            cursor: pointer;
        }

        pre {
            font-family: #{@style.monospace_font};
            max-width: 100%;
        }

        .heading-block {
            background: #f9f9fa;
        }

        .heading-block,
        .output-block {
            padding: 48px;
        }

        @media (max-width: 768px) {
            .heading-block,
            .output-block {
                padding: 32px;
            }
        }

        @media (max-width: 480px) {
            .heading-block,
            .output-block {
                padding: 16px;
            }
        }

        /*
         * Exception logo
         */

        .exception-logo {
            position: absolute;
            right: 48px;
            top: 48px;
            pointer-events: none;
            width: 100%;
        }

        .exception-logo:before {
            content: '';
            display: block;
            height: 64px;
            width: 100%;
            background-size: auto 100%;
            background-image: url("#{@style.logo}");
            background-position: right 0;
            background-repeat: no-repeat;
            margin-bottom: 16px;
        }

        @media (max-width: 768px) {
            .exception-logo {
                position: static;
            }

            .exception-logo:before {
                height: 32px;
                background-position: left 0;
            }
        }

        @media (max-width: 480px) {
            .exception-logo {
                display: none;
            }
        }

        /*
         * Exception info
         */

        /* Compensate for logo placement */
        @media (min-width: 769px) {
            .exception-info {
                max-width: 90%;
            }
        }

        .exception-info > .error,
        .exception-info > .subtext,
        .exception-info > .title {
            margin: 0;
            padding: 0;
        }

        .exception-info > .error {
            font-size: 1em;
            font-weight: 700;
            color: #{@style.primary};
        }

        .exception-info > .subtext {
            font-size: 1em;
            font-weight: 400;
            color: #{@style.accent};
        }

        .exception-info > .title {
            font-size: #{:math.pow(1.2, 4)}em;
            line-height: 1.4;
            font-weight: 300;
            color: #{@style.primary};
        }

        @media (max-width: 768px) {
            .exception-info > .title {
                font-size: #{:math.pow(1.15, 4)}em;
            }
        }

        @media (max-width: 480px) {
            .exception-info > .title {
                font-size: #{:math.pow(1.1, 4)}em;
            }
        }

        .code-block {
            margin: 0;
            font-size: .85em;
            line-height: 1.6;
        }
        </style>
    </head>
    <body>
        <div class="heading-block">
            <aside class="exception-logo"></aside>
            <header class="exception-info">
                <h5 class="error">#{error}</h5>
                <h1 class="title">#{headline}</h1>
                <h5 class="subtext">Console output is shown below.</h5>
            </header>
        </div>
        <div class="output-block">
            <pre class="code code-block">#{format_output(output)}</pre>
        </div>
    </body>
    </html>
    """
  end

  defp format_output(output) do
    output
    |> String.trim()
    |> Plug.HTML.html_escape()
  end

  defp get_error_details(output) do
    case Regex.run(~r/(?:\n|^)\*\* \(([^ ]+)\) (.*)(?:\n|$)/, output) do
      [_, error, headline] -> {error, format_output(headline)}
      _ -> {"CompileError", "Compilation error"}
    end
  end
end
