import Vapor

func routes(_ app: Application) throws {

    let manifestController = ManifestController(publicDirectory: app.directory.publicDirectory)

    app.get { _ in "Серв запущен все работает" }

    app.get("manifest", ":appId", "latest", use: manifestController.getLatestManifest)
    app.get("manifest", ":appId", "version", ":version", use: manifestController.getManifest)
    app.get("manifest", ":appId", "versions", use: manifestController.listManifestVersions)
    app.post("manifest", ":appId", "version", ":version", use: manifestController.updateManifest)
}
