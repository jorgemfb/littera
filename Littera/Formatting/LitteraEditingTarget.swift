import AppKit

/// `NSTextView` de Littera. Atiende los atajos de formato
/// configurados en Ajustes → Atajos (por defecto ⌘B, ⌘I y ⇧⌘K) y lleva los comandos
/// Buscar del menú Edición (⌘F, ⌘G, ⇧⌘G, ⌘E) a la búsqueda de la lupa.
class LitteraEditorTextView: NSTextView {
    weak var editingTarget: LitteraEditingTarget?

    private static let handledFinderActions: Set<NSTextFinder.Action> = [
        .showFindInterface, .showReplaceInterface, .nextMatch, .previousMatch, .setSearchString
    ]

    private func finderAction(for sender: Any?) -> NSTextFinder.Action? {
        guard let item = sender as? NSValidatedUserInterfaceItem,
              let action = NSTextFinder.Action(rawValue: item.tag),
              Self.handledFinderActions.contains(action) else { return nil }
        return action
    }

    override func performTextFinderAction(_ sender: Any?) {
        guard let action = finderAction(for: sender), let editingTarget else {
            super.performTextFinderAction(sender)
            return
        }
        editingTarget.handleFinderAction(action, from: self)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        // «Convertir texto» necesita una selección.
        if item.action == #selector(runEditingCommand(_:)) {
            return isEditable && selectedRange().length > 0
        }
        if item.action == #selector(NSTextView.performTextFinderAction(_:)) {
            guard let action = finderAction(for: item), editingTarget != nil else { return false }
            if action == .setSearchString { return selectedRange().length > 0 }
            if action == .showReplaceInterface { return isEditable }
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        // F1 (keyCode 122) abre la ayuda de Littera.
        if event.keyCode == 122 && event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            LitteraApplicationDelegate.openHelp()
            return true
        }
        if let command = LitteraShortcuts.shared.editingCommand(for: event) {
            LitteraEditingTarget.apply(command, to: self)
            return true
        }
        guard let action = LitteraShortcuts.shared.formatAction(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        LitteraEditingTarget.apply(action, to: self)
        return true
    }

    // MARK: Entrada literal (LIT-002)

    /// Comprobaciones de macOS que reescriben el texto: corrección automática
    /// (incluida la mayúscula inicial), sustituciones de texto, comillas y
    /// rayas tipográficas. Littera no aplica ninguna; la ortografía y la
    /// gramática siguen marcándose sin modificar el Markdown.
    static let rewritingCheckingTypes: NSTextCheckingTypes =
        NSTextCheckingResult.CheckingType.correction.rawValue
        | NSTextCheckingResult.CheckingType.replacement.rawValue
        | NSTextCheckingResult.CheckingType.quote.rawValue
        | NSTextCheckingResult.CheckingType.dash.rawValue

    /// Desactiva las sustituciones automáticas del sistema. El emparejado de
    /// D52 y el subrayado ortográfico no dependen de estas opciones.
    func applyLiteralInputSettings() {
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        inlinePredictionType = .no
        mathExpressionCompletionType = .no
    }

    /// Resultados que no reescriben el texto.
    static func literalResults(_ results: [NSTextCheckingResult]) -> [NSTextCheckingResult] {
        results.filter { $0.resultType.rawValue & rewritingCheckingTypes == 0 }
    }

    /// Último filtro: aunque una opción se reactive desde Edición ›
    /// Sustituciones o desde Ajustes del Sistema (mayúsculas automáticas),
    /// ningún resultado que reescriba el texto llega a aplicarse.
    override func handleTextCheckingResults(
        _ results: [NSTextCheckingResult],
        forRange range: NSRange,
        types checkingTypes: NSTextCheckingTypes,
        options: [NSSpellChecker.OptionKey: Any],
        orthography: NSOrthography,
        wordCount: Int
    ) {
        super.handleTextCheckingResults(
            Self.literalResults(results),
            forRange: range,
            types: checkingTypes & ~Self.rewritingCheckingTypes,
            options: options,
            orthography: orthography,
            wordCount: wordCount
        )
    }

    // MARK: Escritura asistida (D52)

    private var preferences: UserDefaults { .standard }

    private var continuesLists: Bool {
        preferences.object(forKey: LitteraPreferenceKeys.continueLists) as? Bool ?? LitteraPreferenceDefaults.continueLists
    }

    private var closesPairs: Bool {
        preferences.object(forKey: LitteraPreferenceKeys.autoPair) as? Bool ?? LitteraPreferenceDefaults.autoPair
    }

    /// Intro en una lista: siguiente marcador, o fin de la lista si el
    /// elemento está vacío.
    override func insertNewline(_ sender: Any?) {
        if continuesLists, isEditable, !hasMarkedText(),
           let edit = LitteraTextCommands.continueList(in: string, selection: selectedRange()) {
            LitteraEditingTarget.perform(edit, on: self)
            return
        }
        super.insertNewline(sender)
    }

    /// Cierre automático de paréntesis, corchetes, llaves, comillas y
    /// acentos graves. Con texto seleccionado, lo rodea.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if closesPairs, isEditable, !hasMarkedText(), replacementRange.location == NSNotFound,
           let typed, typed.count == 1, let character = typed.first,
           LitteraTextCommands.pairs[character] != nil, selectedRange().length > 0,
           let edit = LitteraTextCommands.autoPair(typing: typed, in: self.string, selection: selectedRange()) {
            LitteraEditingTarget.perform(edit, on: self)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
        guard closesPairs, isEditable, !hasMarkedText(), let typed, typed.count == 1,
              let character = typed.first, selectedRange().length == 0,
              let edit = LitteraTextCommands.completePair(typed: character, in: self.string, caret: selectedRange().location)
        else { return }
        LitteraEditingTarget.perform(edit, on: self, separateUndo: false)
    }

    override func deleteBackward(_ sender: Any?) {
        if closesPairs, isEditable, !hasMarkedText(),
           let edit = LitteraTextCommands.deletePair(in: string, selection: selectedRange()) {
            LitteraEditingTarget.perform(edit, on: self, separateUndo: false)
            return
        }
        super.deleteBackward(sender)
    }

    /// Pegar una URL sobre texto seleccionado crea un enlace Markdown.
    override func paste(_ sender: Any?) {
        if isEditable, !hasMarkedText(),
           let pasted = NSPasteboard.general.string(forType: .string),
           let edit = LitteraTextCommands.linkFromPaste(pasted, in: string, selection: selectedRange()) {
            LitteraEditingTarget.perform(edit, on: self)
            return
        }
        super.paste(sender)
    }

    // MARK: Menú contextual

    /// «Convertir texto» (mayúsculas, minúsculas, capitalizar) sustituye al
    /// submenú «Transformaciones» del sistema, que no deja un paso de Deshacer
    /// propio ni sigue la lengua de la interfaz de Littera.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if let index = menu.items.firstIndex(where: { item in
            item.submenu?.items.contains { $0.action == #selector(NSTextView.uppercaseWord(_:)) } == true
        }) {
            menu.removeItem(at: index)
        }
        let locale = LitteraEditingTarget.interfaceLocale
        let submenu = NSMenu()
        for command in [LitteraEditingCommand.uppercase, .lowercase, .capitalize] {
            let item = NSMenuItem(
                title: L10n.tr(command.label, locale: locale),
                action: #selector(runEditingCommand(_:)),
                keyEquivalent: ""
            )
            item.representedObject = command.rawValue
            item.target = self
            submenu.addItem(item)
        }
        let convert = NSMenuItem(title: L10n.tr("ui.convertir.texto", locale: locale), action: nil, keyEquivalent: "")
        convert.submenu = submenu
        let pasteIndex = menu.items.firstIndex { $0.action == #selector(NSText.paste(_:)) }
        let position = pasteIndex.map { $0 + 1 } ?? 0
        menu.insertItem(.separator(), at: position)
        menu.insertItem(convert, at: position + 1)
        return menu
    }

    @objc func runEditingCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = LitteraEditingCommand(rawValue: raw) else { return }
        LitteraEditingTarget.apply(command, to: self)
    }
}

/// Editor que recibe los comandos de formato de la paleta: el editor Fuente
/// visible (también en Dividido).
@MainActor
final class LitteraEditingTarget {
    private weak var textView: NSTextView?
    /// Último editor registrado. En Vista previa sigue existiendo, oculto: las
    /// propiedades se cambian a través de él para que el cambio entre en su
    /// historial de deshacer (si no, volver a Fuente lo vaciaba).
    private weak var documentTextView: NSTextView?

    /// La vista del editor abre la búsqueda de la lupa o repite la última.
    var onFindRequest: ((NSTextFinder.Action, String?) -> Void)?

    func register(_ textView: NSTextView) {
        self.textView = textView
        documentTextView = textView
        (textView as? LitteraEditorTextView)?.editingTarget = self
    }

    func unregister(_ textView: NSTextView) {
        if self.textView === textView { self.textView = nil }
        if let editor = textView as? LitteraEditorTextView, editor.editingTarget === self {
            editor.editingTarget = nil
        }
    }

    /// Devuelve el foco al editor activo (por ejemplo, al cerrar la búsqueda).
    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Acción Buscar recibida sin que el editor sea el primer respondedor
    /// (por ejemplo, justo después de abrir la ventana o cerrar una paleta).
    func requestFinderAction(_ action: NSTextFinder.Action) {
        guard let textView else { return }
        handleFinderAction(action, from: textView)
    }

    func handleFinderAction(_ action: NSTextFinder.Action, from textView: NSTextView) {
        guard textView === self.textView else { return }
        var selection: String?
        if action == .setSearchString {
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            selection = (textView.string as NSString).substring(with: range)
        }
        onFindRequest?(action, selection)
    }

    /// Selecciona y muestra la coincidencia que corresponde a `direction`.
    /// Sin editor (Vista previa) devuelve `nil`.
    @discardableResult
    func search(_ query: String, direction: LitteraSearchDirection) -> LitteraSearchResult? {
        guard let textView else { return nil }
        let matches = LitteraTextSearch.matches(of: query, in: textView.string)
        guard let index = LitteraTextSearch.index(
            in: matches,
            selection: textView.selectedRange(),
            direction: direction
        ) else { return LitteraSearchResult.none }
        let range = matches[index]
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        return LitteraSearchResult(current: index + 1, total: matches.count)
    }

    var isAvailable: Bool { textView != nil }

    /// Cambia una clave del frontmatter en el editor, como un paso de
    /// deshacer. Devuelve `false` si no hay editor (Vista previa).
    @discardableResult
    /// `documentText` es el texto del documento activo: el editor solo se usa
    /// si contiene exactamente ese texto (el mismo documento, sin desfase).
    func setDocumentProperty(_ key: String, to value: String?, documentText: String) -> Bool {
        guard let textView = textView ?? documentTextView, textView.window != nil, textView.isEditable,
              !textView.hasMarkedText(), textView.string == documentText else { return false }
        if let edit = LitteraDocumentProperties.edit(
            setting: key,
            to: value,
            in: textView.string,
            selection: textView.selectedRange(),
            language: Self.interfaceLocale.language.languageCode?.identifier ?? "es"
        ) {
            Self.perform(edit, on: textView)
        }
        return true
    }

    /// Aplica el comando al editor activo y le devuelve el foco.
    func apply(_ action: LitteraFormattingAction) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        Self.apply(action, to: textView)
    }

    /// Comando de edición (D52) en el editor activo.
    func apply(_ command: LitteraEditingCommand) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        Self.apply(command, to: textView)
    }

    static func apply(_ action: LitteraFormattingAction, to textView: NSTextView) {
        let edit = LitteraMarkdownFormatter.edit(
            for: action,
            in: textView.string,
            selection: textView.selectedRange()
        )
        perform(edit, on: textView)
    }

    static func apply(_ command: LitteraEditingCommand, to textView: NSTextView) {
        let defaults = UserDefaults.standard
        let format = defaults.string(forKey: LitteraPreferenceKeys.dateFormat)
            .flatMap(LitteraDateFormat.init(rawValue:)) ?? .iso
        let context = LitteraTextCommands.Context(date: Date(), dateFormat: format, locale: interfaceLocale)
        guard let edit = LitteraTextCommands.edit(
            for: command,
            in: textView.string,
            selection: textView.selectedRange(),
            context: context
        ) else {
            NSSound.beep()
            return
        }
        perform(edit, on: textView)
    }

    /// Lengua de la interfaz de Littera (no la del sistema).
    static var interfaceLocale: Locale {
        let language = UserDefaults.standard.string(forKey: LitteraLanguage.settingKey) ?? LitteraLanguage.fallback
        return LitteraLanguage.locale(for: language)
    }

    /// Un comando es un único reemplazo registrado en Deshacer, con la
    /// selección resultante y el cambio visible. `separateUndo: false` deja
    /// que se agrupe con lo que se está escribiendo (cierre de símbolos).
    static func perform(_ edit: LitteraTextEdit, on textView: NSTextView, separateUndo: Bool = true) {
        guard textView.isEditable, !textView.hasMarkedText(),
              let storage = textView.textStorage else { return }
        if edit.range.length == 0, edit.replacement.isEmpty {
            textView.setSelectedRange(edit.selection)
            return
        }
        if separateUndo { textView.breakUndoCoalescing() }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        if separateUndo { textView.breakUndoCoalescing() }
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
    }

    /// Reemplaza la coincidencia seleccionada y pasa a la siguiente. Si la
    /// selección no es una coincidencia, solo busca la siguiente.
    @discardableResult
    func replaceCurrent(_ query: String, with replacement: String) -> LitteraSearchResult? {
        guard let textView else { return nil }
        let selection = textView.selectedRange()
        let matches = LitteraTextSearch.matches(of: query, in: textView.string)
        if matches.contains(selection), Self.canEdit(textView),
           textView.shouldChangeText(in: selection, replacementString: replacement) {
            textView.breakUndoCoalescing()
            textView.textStorage?.replaceCharacters(in: selection, with: replacement)
            textView.didChangeText()
            textView.breakUndoCoalescing()
            textView.setSelectedRange(NSRange(location: selection.location + (replacement as NSString).length, length: 0))
            return search(query, direction: .incremental)
        }
        return search(query, direction: .next)
    }

    /// Reemplaza todas las coincidencias en un único paso de Deshacer.
    /// Devuelve el número de reemplazos.
    @discardableResult
    func replaceAll(_ query: String, with replacement: String) -> Int {
        guard let textView, Self.canEdit(textView), let storage = textView.textStorage else { return 0 }
        let matches = LitteraTextSearch.matches(of: query, in: textView.string)
        guard !matches.isEmpty else { return 0 }
        let ranges = matches.map { NSValue(range: $0) }
        let strings = Array(repeating: replacement, count: matches.count)
        guard textView.shouldChangeText(inRanges: ranges, replacementStrings: strings) else { return 0 }
        textView.breakUndoCoalescing()
        storage.beginEditing()
        for range in matches.reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.breakUndoCoalescing()
        let first = NSRange(location: matches[0].location, length: (replacement as NSString).length)
        textView.setSelectedRange(first)
        textView.scrollRangeToVisible(first)
        return matches.count
    }

    private static func canEdit(_ textView: NSTextView) -> Bool {
        textView.isEditable && !textView.hasMarkedText()
    }
}
