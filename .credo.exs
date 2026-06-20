%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
      },
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 98}
      ]
    }
  ]
}
