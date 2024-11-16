[
  {:exa_core, [git: "https://github.com/red-jade/exa_core.git", tag: "v0.3.2"]},
  {:exa_std, [git: "https://github.com/red-jade/exa_std.git", tag: "v0.3.2"]},
  {:exa_space,
   [git: "https://github.com/red-jade/exa_space.git", tag: "v0.3.2"]},
  {:exa_color,
   [git: "https://github.com/red-jade/exa_color.git", tag: "v0.3.2"]},
  {:exa_json, [git: "https://github.com/red-jade/exa_json.git", tag: "v0.3.2"]},
  {:dialyxir, "~> 1.0", [only: [:dev, :test], runtime: false]},
  {:ex_doc, "~> 0.30", [only: [:dev, :test], runtime: false]},
  {:benchee, "~> 1.0", [only: [:dev, :test], runtime: false]}
]