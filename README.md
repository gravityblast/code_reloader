# CodeReloader

Code reloader Plug extracted from [Phoenix](https://github.com/phoenixframework/phoenix/) and adapted to be a generic Plug.

## Why

If you have an Elixir web app using only Plug without Phoenix, you need to restart it everytime you update the code.

This module uses `Mix` to compile any files changed on disk every time an HTTP request is received, allowing your server to keep running while you make changes.

If code changes outside of the VM e.g. you call `mix compile` in another shell, or your editor recompiles files automatically, any modules that changed on disk will be re-loaded (the Pheonix version doesn't currently handle this use case).

## Usage

Add the `CodeReloader.Server` to your supervision tree, e.g. in your `Application.start/2`:

```
children = [
  ..., {CodeReloader.Server, [:elixir]}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

The list argument configures the compilers we run when when `CodeReloader.Server.reload!/1` is called: each is called (effectively) as `mix compile.<name>`.


For re-loading code on every HTTP request, add the plug to your `Plug.Router`:

```
plug CodeReloader.Plug, endpoint: __MODULE__
```

The endpoint is used to serialize requests and prevent a compile failure in the router from stopping subsequent re-loading.

If your code has compile errors, an error page will be rendered to the browser; errors and other compile messages also appear on the standard output.


### Using outside of Plug

You can also call `CodeReloader.Server.reload!/1` directly, e.g. for reloading on another event.

```
CodeReloader.Server.reload!(__MODULE__)
```
