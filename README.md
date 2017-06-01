# CodeReloader

Code reloader Plug extracted from [Phoenix](https://github.com/phoenixframework/phoenix/) and adapted to be a generic Plug.

So far it's just a proof of concept to understand if having a generic code reload Plug makes sense or not.

## Why

If you have an Elixir web app using only Plug without Phoenix, you need to restart it everytime you update the code.

## Usage

The the example app at [https://github.com/pilu/code-reload-example](https://github.com/pilu/code-reload-example)
