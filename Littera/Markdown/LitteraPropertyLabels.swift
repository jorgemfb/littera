import Foundation

/// Nombres en el idioma de la interfaz para las claves habituales del
/// frontmatter (D55). En el YAML las claves siguen en inglés; el panel de
/// propiedades muestra el nombre traducido y la clave real como ayuda.
enum LitteraPropertyLabels {
    /// Clave YAML (en minúsculas, con `_`) → clave de localización.
    static let localizationKeys: [String: String] = [
        "subtitle": "ui.clave.subtitle",
        "description": "ui.clave.description",
        "summary": "ui.clave.summary",
        "abstract": "ui.clave.abstract",
        "excerpt": "ui.clave.excerpt",
        "slug": "ui.clave.slug",
        "aliases": "ui.clave.aliases",
        "alias": "ui.clave.alias",
        "author": "ui.clave.author",
        "authors": "ui.clave.authors",
        "contributors": "ui.clave.contributors",
        "editor": "ui.clave.editor",
        "publisher": "ui.clave.publisher",
        "owner": "ui.clave.owner",
        "assignee": "ui.clave.assignee",
        "reviewer": "ui.clave.reviewer",
        "reviewers": "ui.clave.reviewers",
        "copyright": "ui.clave.copyright",
        "license": "ui.clave.license",
        "date": "ui.clave.date",
        "modified": "ui.clave.modified",
        "updated": "ui.clave.updated",
        "lastmod": "ui.clave.lastmod",
        "last_modified": "ui.clave.last_modified",
        "published": "ui.clave.published",
        "publish_date": "ui.clave.publish_date",
        "deadline": "ui.clave.deadline",
        "due": "ui.clave.due",
        "due_date": "ui.clave.due_date",
        "start_date": "ui.clave.start_date",
        "end_date": "ui.clave.end_date",
        "categories": "ui.clave.categories",
        "category": "ui.clave.category",
        "keywords": "ui.clave.keywords",
        "lang": "ui.clave.lang",
        "language": "ui.clave.language",
        "locale": "ui.clave.locale",
        "translation_of": "ui.clave.translation_of",
        "translations": "ui.clave.translations",
        "version": "ui.clave.version",
        "revision": "ui.clave.revision",
        "priority": "ui.clave.priority",
        "progress": "ui.clave.progress",
        "project": "ui.clave.project",
        "requirements": "ui.clave.requirements",
        "milestone": "ui.clave.milestone",
        "release": "ui.clave.release",
        "target_release": "ui.clave.target_release",
        "platform": "ui.clave.platform",
        "platforms": "ui.clave.platforms",
        "custom": "ui.clave.custom",
        "type": "ui.clave.type",
        "draft": "ui.clave.draft",
        "layout": "ui.clave.layout",
        "template": "ui.clave.template",
        "permalink": "ui.clave.permalink",
        "url": "ui.clave.url",
        "link": "ui.clave.link",
        "links": "ui.clave.links",
        "image": "ui.clave.image",
        "cover": "ui.clave.cover",
        "thumbnail": "ui.clave.thumbnail",
        "series": "ui.clave.series",
        "source": "ui.clave.source",
        "audience": "ui.clave.audience",
        "email": "ui.clave.email",
        "organization": "ui.clave.organization",
        "company": "ui.clave.company",
        "location": "ui.clave.location",
        "notes": "ui.clave.notes",
        "comments": "ui.clave.comments",
        "related": "ui.clave.related",
        "references": "ui.clave.references",
        "dependencies": "ui.clave.dependencies",
        "reading_time": "ui.clave.reading_time",
        "word_count": "ui.clave.word_count",
        "visibility": "ui.clave.visibility",
        "rating": "ui.clave.rating",
        "weight": "ui.clave.weight",
        "order": "ui.clave.order",
        "folder": "ui.clave.folder",
        "collection": "ui.clave.collection",
        "parent": "ui.clave.parent",
    ]

    /// Nombre para mostrar: traducido si la clave es conocida; si no, la
    /// clave legible (`target_release` → «Target release»).
    static func label(for key: String, locale: Locale) -> String {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        if let localizationKey = localizationKeys[normalized] {
            return L10n.tr(localizationKey, locale: locale)
        }
        return humanized(key)
    }

    static func humanized(_ key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let first = words.first else { return key }
        return first.uppercased() + words.dropFirst()
    }
}
