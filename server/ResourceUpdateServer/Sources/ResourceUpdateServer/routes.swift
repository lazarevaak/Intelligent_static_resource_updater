import Vapor

func routes(_ app: Application) throws {
    let manifestController = ManifestController(publicDirectory: app.directory.publicDirectory)

    app.get { _ in "Серв запущен все работает" }
    let v1 = app.grouped("v1")
    v1.get("manifest", ":appId", "latest", use: manifestController.getLatestManifest)
    v1.get("manifest", ":appId", "version", ":version", use: manifestController.getManifest)
    v1.post("manifest", ":appId", "version", ":version", use: manifestController.updateManifest)
    v1.get("patch", ":appId", "from", ":fromVersion", "to", ":toVersion", "meta", use: manifestController.getPatchMeta)
}
