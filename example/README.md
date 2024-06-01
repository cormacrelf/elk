# Elk example

Prerequisites:
- `pipx` and `pipx install poetry`
- A recent `buck2`, roughly 
  [2024-05-15](https://github.com/facebook/buck2/releases/tag/2024-05-15) 
  should have the bundled prelude necessary to run the example.

1. Install the elk plugin. From this repository root, run

       pipx install poetry
       pipx inject poetry .

2. In the `example/pypi` folder, run

       poetry elk

   This writes the `example/pypi/BUCK` file.
   There should be no changes until you add dependencies:

       poetry add polars
       poetry elk

3. In the `example` folder, run

       buck2 run :main

   The dependencies for :main are in `example/BUCK`.
   If you added a dependency in poetry, you'll have to add it as 
   `//pypi:some_pkg` in there.
