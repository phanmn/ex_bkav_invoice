defmodule ExBkavInvoice.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/phanmn/ex_bkav_invoice"

  def project do
    [
      app: :ex_bkav_invoice,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Client for the Bkav eHoadon (hóa đơn điện tử) SOAP web service.",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Only Req.request/1 and %Req.Response{} are used, and both behave the same
      # across 0.6 and 0.7 — the wider range lets a host application on either
      # line adopt this without moving its whole HTTP stack.
      {:req, "~> 0.6 or ~> 0.7"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.20", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "ExBkavInvoice",
      extras: ["README.md"]
    ]
  end
end
