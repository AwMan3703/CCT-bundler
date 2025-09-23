# CC:Tweaked LUA bundler
Bundles a script and its dependencies (APIs and such, imported with `require()`)
#### Note that:
The bundling operation is not recursive, nested dependencies will be preserved: if script **A** `require`s script **B** and script **B** `require`s script **C**, when script **A** is bundled and script **B** is built into it, script **C** will still be required as an external file. To obtain a single file, script **C** would first need to be bundled in script **B**, before script **B** is built into script **A**.

Furthermore, only explicitly declared imports will be bundled.
```
local lib = require("mylibrary")
```
The above dependency will be included, whereas the following will not:
```
local libname = "mylibrary"
local lib = require(libname)
```



## How to use
1. Import or download the `bundler.lua` script to a computer.
2. Use the `bundler build <script-path>.lua` command to bundle scripts (see "commands > build").
3. The bundled file will be saved at `<script-path>_bundled.lua`.
4. You can now remove all dependencies from the computer — the bundled script will run fine on its own.

## Commands
### `bundler build <script-path> <output-path>`
Builds a bundle by looking for `require()` statements in the script at `<script-path>` and replacing them with the code they import from other files. The resulting script is then saved at `<output-path>`.
- `<script-path>` The path of the script to bundle up.
- `<output-path>` (OPTIONAL) The location to save the newly built bundle in. If this parameter is omitted, it defaults to the same directory as `<script-path>`, naming the new file "`<original-name>_bundled.lua`".
### `bundler test <script-path>`
Temporarily builds and runs a bundle. This command is meant to test if your script would run when bundled, without creating new files.
- `<script-path>` The path of the script to test.