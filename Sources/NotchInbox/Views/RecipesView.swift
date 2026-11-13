import AppKit
import SwiftUI

/// The Recipes page of the agent room: jobs you hand out often, saved to run again. A
/// recipe's job can have blanks, written in curly brackets, that are filled in on each run.
struct RecipesView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: RecipesStore
    @ObservedObject var assistant: Assistant

    var body: some View {
        if let recipe = store.book.recipe(model.recipeOpen) {
            RecipePage(model: model, store: store, recipe: recipe, start: { run(recipe.id) })
                .id(recipe.id)
        } else {
            RecipeList(model: model, recipes: store.book.ordered, run: run)
        }
    }

    private func run(_ id: UUID) {
        // Nothing can do the work yet: the assistant's page says what to set up.
        if !assistant.status.isReady && assistant.status != .checking {
            model.openAssistant()
            return
        }
        model.runRecipe(id)
    }
}

/// Every recipe: the ones you ran most recently first.
struct RecipeList: View {
    @ObservedObject var model: NotchModel
    let recipes: [Recipe]
    let run: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Recipes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Jobs you hand out often")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                SmallPill(title: "New Recipe", symbol: "plus", action: { model.newRecipe() })
                    .help("Write a new recipe from scratch")
            }
            if recipes.isEmpty {
                Text("No recipes yet. Write one with New Recipe, or type a job in the box below and click the book beside it to keep it.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(recipes) { recipe in
                            RecipeRow(recipe: recipe, open: { model.showRecipe(recipe.id) }, run: { run(recipe.id) })
                                .contextMenu {
                                    Button("Open") { model.showRecipe(recipe.id) }
                                    Divider()
                                    Button("Delete This Recipe") { model.removeRecipe(recipe.id) }
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One recipe in the list: its name and its job. One with no blanks runs straight from here.
struct RecipeRow: View {
    let recipe: Recipe
    let open: () -> Void
    let run: () -> Void
    @State var hovering = false

    var body: some View {
        let blanks = recipe.blanks.count

        HStack(spacing: 10) {
            Image(systemName: recipe.chain ? "link" : "text.book.closed.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.avatar))
                .help(recipe.chain ? "It goes to a chain: " + AgentChain.line(for: .write) : "It goes to one agent")
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(recipe.line)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if blanks == 0 {
                SmallPill(title: "Run", symbol: "play.fill", action: run)
                    .help(recipe.chain ? "Start a chain on this job now" : "Start an agent on this job now")
            } else {
                Text(blanks == 1 ? "1 blank" : "\(blanks) blanks")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.hover.opacity(0.55) : Color.clear))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help(blanks == 0 ? "Open it to change it" : "Open it to fill in its blanks and run it")
        .accessibilityLabel(Text(recipe.title))
        .accessibilityAddTraits(.isButton)
    }
}

/// One recipe: change its name and its job, fill in its blanks, and start it. Everything
/// is saved as it's typed.
struct RecipePage: View {
    @ObservedObject var model: NotchModel
    let store: RecipesStore
    let recipe: Recipe
    let start: () -> Void
    /// The blank being typed in, by its key.
    @FocusState private var typing: String?

    init(model: NotchModel, store: RecipesStore, recipe: Recipe, start: @escaping () -> Void) {
        self.model = model
        self.store = store
        self.recipe = recipe
        self.start = start
    }

    var body: some View {
        let blanks = recipe.blanks
        let ready = recipe.isReady(with: model.recipeBlanks)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconButton(symbol: "chevron.left", label: "Back to your recipes", size: 26, action: { model.closeRecipe() })
                TextField("Name it, like “Practice questions”", text: text(\.name))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 6)
                ChainToggle(on: chain)
                IconButton(symbol: "trash", label: "Delete this recipe", size: 26, action: { model.removeRecipe(recipe.id) })
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 9) {
                    RecipeJobField(text: text(\.text))
                    if !blanks.isEmpty {
                        RecipeBlanks(blanks: blanks, values: $model.recipeBlanks, typing: $typing, submit: start)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 10) {
                Text(recipe.hint(with: model.recipeBlanks))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                PillButton(title: recipe.chain ? "Start a Chain" : "Start an Agent", prominent: ready, action: start)
                    .help(ready ? "Hand this job out now" : "Fill in the job and its blanks first")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Opened to be run: the first empty blank is ready to type in. (Only when the
        // recipe opens, so that writing a blank into the job doesn't move your typing.)
        .onAppear {
            typing = Recipe.firstEmpty(of: recipe.blanks, in: model.recipeBlanks)
        }
    }

    /// Its name or its job, read from the recipes as it's typed.
    private func text(_ part: WritableKeyPath<Recipe, String>) -> Binding<String> {
        let id = recipe.id
        return Binding(
            get: { store.book.recipe(id)?[keyPath: part] ?? "" },
            set: { typed in model.changeRecipe(id) { $0[keyPath: part] = typed } }
        )
    }

    private var chain: Binding<Bool> {
        let id = recipe.id
        return Binding(
            get: { store.book.recipe(id)?.chain ?? false },
            set: { on in model.changeRecipe(id) { $0.chain = on } }
        )
    }
}

/// The recipe's job. Anything in curly brackets is a blank to fill in on each run.
struct RecipeJobField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            AgentCaption(text: "The job")
            TextField("What to find out, write or compare. Put what changes each time in curly brackets, like {topic}.", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .lineLimit(2...8)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lane))
        }
    }
}

/// A box for each blank in the job. Return goes on to the next empty one, and from the
/// last it starts the job.
struct RecipeBlanks: View {
    let blanks: [String]
    @Binding var values: [String: String]
    let typing: FocusState<String?>.Binding
    let submit: () -> Void

    private static let columns = [GridItem(.adaptive(minimum: 170), spacing: 8, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AgentCaption(text: blanks.count == 1 ? "Fill in the blank" : "Fill in the blanks")
            LazyVGrid(columns: RecipeBlanks.columns, alignment: .leading, spacing: 8) {
                ForEach(blanks, id: \.self) { blank in
                    EditorField(label: Recipe.label(blank)) {
                        TextField("", text: value(blank))
                            .focused(typing, equals: Recipe.key(blank))
                    }
                }
            }
            .onSubmit(entered)
        }
    }

    private func value(_ blank: String) -> Binding<String> {
        let key = Recipe.key(blank)
        return Binding(
            get: { values[key] ?? "" },
            set: { typed in values[key] = typed }
        )
    }

    private func entered() {
        if let next = Recipe.firstEmpty(of: blanks, in: values) {
            typing.wrappedValue = next
        } else {
            submit()
        }
    }
}
