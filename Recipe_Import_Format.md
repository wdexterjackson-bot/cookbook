# Recipe bulk-import file format

Used by the Administrator screen's **Import Recipes from File** action (Profile → Administrator → Import Recipes from File) to load multiple recipes from a single plain-text (`.txt`) file into a personal cookbook you choose.

Each recipe is parsed by the same on-device AI used for single-recipe paste-import, so the ingredient and step lines don't need to follow a rigid format — write them the way you normally would. Only a few labeled lines are load-bearing.

## The one required rule

**Every recipe in the file must start with a line beginning `Name:`.** That's how the file is split into separate recipes — everything from one `Name:` line up to (not including) the next one is treated as a single recipe. Any text before the first `Name:` line in the file is ignored.

(This is different from creating a single recipe by pasting text into the app directly, where a missing title is tolerated — in a bulk file it's required, since it's what separates one recipe from the next.)

## Optional labeled lines

- **`Section:`** — which chapter of the target cookbook this recipe belongs to (e.g. `Section: Desserts`). Matched by name, case-insensitively, against the chapters already configured on the cookbook you're importing into. If it doesn't match an existing chapter, the recipe is still imported — just left unfiled. A new chapter is never created automatically.
- **`By:`** — who this recipe is credited to. Either just a name (`By: Jane Doe`) or a name with a location (`By: Jane Doe of Baltimore, MD`, or `By: Jane Doe of Toronto, Canada` outside the US). This is preserved exactly as written and becomes that recipe's permanent author credit — it's never changed again, even if you later import the same recipe again or edit it.

  If a recipe has no `By:` line, it's credited to whoever is doing the import instead (your own name and location, if you've set them in Settings — otherwise you'll be asked once, before the whole file starts importing, whether to add your name or import everything as Anonymous).
- **`Notes:`** — anything that isn't itself a cooking instruction: serving size, substitution ideas, storage tips, and so on. If you don't include this label, trailing commentary after the last real step is still usually recognized as notes rather than folded into the steps.

## Ingredients and steps

Everything else in a recipe's block — the lines that aren't `Name:`, `Section:`, `By:`, or `Notes:` — is classified automatically as either an ingredient or an instruction step, in the order it appears. Quantities and units are split out from ingredient lines where possible (e.g. "2 cups flour" → quantity 2, unit "cup", ingredient "flour"); a line like "salt to taste" that doesn't have a clear quantity is kept as-is.

## Example — two recipes in one file

```
Name: Skillet Cornbread
Section: Breads
By: Mary Jackson of Memphis, TN

2 cups cornmeal
1 cup buttermilk
2 eggs
1 tsp salt

Preheat the oven to 425°F with a cast iron skillet inside.
Whisk the dry ingredients, then stir in the buttermilk and eggs.
Pour into the hot skillet and bake 20 minutes.

Notes: Best served warm, straight from the skillet.

Name: Pumpkin Pie
Section: Desserts
By: Grandma Jackson

1 can pumpkin puree
3/4 cup sugar
1 unbaked pie crust

Whisk pumpkin, sugar, and spices together.
Pour into the crust and bake at 350°F for 50 minutes.

Feeds 6-8. Freezes well for up to a month.
```

In this example, the second recipe's "Feeds 6-8. Freezes well for up to a month." has no `Notes:` label but is still recognized as notes rather than an instruction step, since it doesn't read as a cooking action.

## What happens if a recipe can't be parsed

If one recipe block in the file can't be understood (for example, `Name:` is present but nothing else about it is clear), it's skipped and the rest of the file still imports normally. The results screen after import lists anything that was skipped so you can fix and re-import just those.
