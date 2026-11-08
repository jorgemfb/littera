//  LitteraCommandRegistry.swift
//  Littera 2.0 · Etapa 5 · Registro único de comandos (D72)
//
//  CÓMO AÑADIR UNA FUNCIÓN: una entrada `LitteraCommand` en su sección (o una
//  sección nueva en `all`). Con eso aparece en la paleta (⌘K), se puede buscar
//  por título, grupo o palabras clave y, si tiene id en LitteraShortcuts, se
//  muestra su atajo configurado. La paleta y el anfitrión de la ventana no se
//  tocan: ejecutan `perform` sin saber qué hace.
//
//  `perform` solo publica una notificación o cambia una preferencia; quien
//  hace el trabajo (anfitrión, editor, contenedor) la escucha.

import Foundation

struct LitteraCommand: Identifiable {
    /// Menú de la barra de menús donde aparece solo (además de la paleta).
    enum Menu { case view, tools }

    let id: String
    /// Claves de localización.
    let title: String
    let group: String
    let symbol: String
    /// Atajo por defecto si el comando no está en LitteraShortcuts.
    var shortcut: String? = nil
    /// Términos extra de búsqueda (claves de localización o texto literal).
    var keywords: [String] = []
    /// Solo con un editor que admita edición (no en Vista previa).
    var requiresEditing = false
    /// Lleva al espacio de trabajo antes de ejecutarse.
    var showsEditor = false
    /// Si se indica, el comando aparece en ese menú con su atajo configurado.
    var menu: Menu? = nil
    let perform: () -> Void
}

/// Modelo de presentación usado por las pruebas y por cualquier lista de
/// comandos que no necesite ejecutarlos.
struct LitteraPaletteCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let group: String
    let symbol: String
    let shortcut: String?
    let enabled: Bool
}

enum LitteraCommandRegistry {
    /// Todos los comandos, en el orden en que se muestran.
    static var all: [LitteraCommand] {
        views + documents + tools + appearance + formatting + editing + export
    }

    static func command(_ id: String) -> LitteraCommand? {
        all.first { $0.id == id }
    }

    /// Atajo visible: el configurado en Ajustes → Atajos o el por defecto.
    static func shortcut(for command: LitteraCommand) -> String? {
        LitteraShortcuts.definition(command.id) == nil
            ? command.shortcut
            : LitteraShortcuts.shared.display(for: command.id)
    }

    static func commands(canEdit: Bool) -> [LitteraPaletteCommand] {
        all.map {
            LitteraPaletteCommand(
                id: $0.id, title: $0.title, group: $0.group, symbol: $0.symbol,
                shortcut: shortcut(for: $0),
                enabled: !$0.requiresEditing || canEdit
            )
        }
    }

    static func editingCommand(for commandID: String) -> LitteraEditingCommand? {
        guard commandID.hasPrefix("edit.") else { return nil }
        return LitteraEditingCommand(rawValue: String(commandID.dropFirst("edit.".count)))
    }

    static func formatAction(for commandID: String) -> LitteraFormattingAction? {
        guard commandID.hasPrefix("format.") else { return nil }
        return LitteraFormattingAction(rawValue: String(commandID.dropFirst("format.".count)))
    }

    // MARK: Secciones

    private static var views: [LitteraCommand] {
        [
            mode("source", .source, "ui.cambiar.a.fuente", "chevron.left.forwardslash.chevron.right"),
            mode("split", .split, "ui.cambiar.a.dividido", "rectangle.split.2x1"),
            mode("preview", .preview, "ui.cambiar.a.vista.previa", "eye")
        ]
    }

    private static var documents: [LitteraCommand] {
        [
            .init(id: "new", title: "ui.nuevo.documento.markdown", group: "ui.documentos", symbol: "doc.badge.plus", shortcut: "⌘N", perform: post(.litteraNewDocument)),
            .init(id: "open", title: "ui.abrir.documento", group: "ui.documentos", symbol: "folder", shortcut: "⌘O", perform: post(.litteraOpenDocument)),
            .init(id: "documents.switch", title: "ui.cambiar.de.documento.abierto", group: "ui.documentos", symbol: "doc.on.doc", shortcut: "⇧⌘O", perform: post(.litteraShowDocuments)),
            .init(id: "save", title: "ui.guardar.documento", group: "ui.documentos", symbol: "square.and.arrow.down", shortcut: "⌘S", perform: post(.litteraSaveDocument)),
            .init(id: "saveAs", title: "ui.guardar.como", group: "ui.documentos", symbol: "square.and.arrow.down.on.square", perform: post(.litteraSaveAsDocument)),
            .init(id: "close", title: "ui.cerrar.documento", group: "ui.documentos", symbol: "xmark.square", shortcut: "⌘W", perform: post(.litteraCloseDocument))
        ]
    }

    private static var tools: [LitteraCommand] {
        [
            editorCommand("properties", "ui.propiedades.del.documento", "ui.herramientas.2", "slider.horizontal.3"),
            editorCommand("stats", "ui.estadisticas.del.documento", "ui.herramientas.2", "chart.bar.xaxis")
        ]
    }

    private static var appearance: [LitteraCommand] {
        [
            width("narrow", .narrow, "ui.anchura.estrecha"),
            width("medium", .medium, "ui.anchura.media"),
            width("wide", .wide, "ui.anchura.ancha"),
            width("available", .available, "ui.anchura.disponible")
        ]
    }

    private static var formatting: [LitteraCommand] {
        let groups: [LitteraFormattingAction.Group: String] = [
            .inline: "ui.formato.de.texto",
            .blocks: "ui.parrafos.y.encabezados",
            .lists: "ui.listas",
            .insert: "ui.insertar"
        ]
        let defaults: [LitteraFormattingAction: String] = [.bold: "⌘B", .italic: "⌘I", .link: "⇧⌘K"]
        return LitteraFormattingAction.allCases.map { format in
            var command = editorCommand("format.\(format.rawValue)", format.label, groups[format.group] ?? "ui.formato.2", format.symbol)
            command.shortcut = defaults[format]
            command.requiresEditing = true
            return command
        }
    }

    private static var editing: [LitteraCommand] {
        LitteraEditingCommand.allCases.map { command in
            var entry = editorCommand(command.commandID, command.label, "ui.edicion", command.symbol)
            entry.requiresEditing = true
            return entry
        }
    }

    private static var export: [LitteraCommand] {
        [
            .init(id: "export.pdf", title: "ui.exportar.como.pdf", group: "ui.exportacion", symbol: "doc.richtext", perform: post(.litteraExportPDF)),
            .init(id: "export.html", title: "ui.exportar.como.html", group: "ui.exportacion", symbol: "chevron.left.forwardslash.chevron.right", perform: post(.litteraExportHTML))
        ]
    }

    // MARK: Constructores

    private static func post(_ name: Notification.Name, _ object: String? = nil) -> () -> Void {
        { NotificationCenter.default.post(name: name, object: object) }
    }

    private static func mode(_ id: String, _ mode: LitteraEditorMode, _ title: String, _ symbol: String) -> LitteraCommand {
        .init(id: id, title: title, group: "ui.vistas", symbol: symbol, showsEditor: true,
              perform: post(.litteraSetMode, mode.rawValue))
    }

    /// Comandos que resuelve el editor (tiene la selección y el modo).
    private static func editorCommand(_ id: String, _ title: String, _ group: String, _ symbol: String) -> LitteraCommand {
        .init(id: id, title: title, group: group, symbol: symbol, showsEditor: true,
              perform: post(.litteraEditorCommand, id))
    }

    /// El editor observa la preferencia: no hace falta avisarle.
    private static func width(_ id: String, _ width: LitteraWritingWidth, _ title: String) -> LitteraCommand {
        .init(id: id, title: title, group: "ui.apariencia.2", symbol: "text.aligncenter") {
            UserDefaults.standard.set(width.rawValue, forKey: LitteraPreferenceKeys.writingWidth)
        }
    }
}
