//
//  Persistence.swift
//  QR Pop
//
//  Created by Shawn Davis on 4/12/23.
//

//
//  Persistence.swift
//  QR Pop
//
//  Created by Shawn Davis on 3/11/23.
//

import CoreData
import CloudKit
import SwiftUI
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif
import OSLog

class Persistence: ObservableObject {
#if !targetEnvironment(simulator)
    static let shared = Persistence()
#endif
    
    // Disables writing anything to an actual store.
    private let inMemory: Bool
    
#if canImport(CoreSpotlight)
    private(set) var spotlightIndexer: SpotlightDelegate?
#endif
    
    /// A Boolean that is true if iCloud is available on this device.
    var cloudAvailable: Bool = {
        FileManager.default.ubiquityIdentityToken != nil
    }()
    
    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }
    
    lazy var container: NSPersistentCloudKitContainer = {
        setupContainer()
    }()
    
    /// Prepares the `NSPersistentCloudKitContainer` depending on a variety of parameters.
    /// - If `useCloudSync` is enabled in `UserDefaults.appGroup` the container will be created with `CloudKitContainerOptions`
    /// - If `inMemory` is `true` the container will be initialized with no permanent store and no access to CloudKit.
    private func setupContainer() -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "Database")
        var description: NSPersistentStoreDescription
        
        if !inMemory {
            let storeURL = URL.storeURL(for: Constants.groupIdentifier, databaseName: "Database")
            description = NSPersistentStoreDescription(url: storeURL)
        } else {
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        }
        
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier:"iCloud.shwndvs.QR-Pop")
        
        container.persistentStoreDescriptions = [description]
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                logger.error("The container could not be loaded: \(error.localizedDescription)")
                debugPrint(error)
            }
        })
        
#if canImport(CoreSpotlight)
        let coordinator = container.persistentStoreCoordinator
        self.spotlightIndexer = SpotlightDelegate(
            forStoreWith: description,
            coordinator: coordinator)
        self.toggleSpotlightIndexing(enabled: true)
#endif
        
        return container
    }
}

// MARK: - Simulated Data

extension Persistence {
    
#if targetEnvironment(simulator)
    static let shared = Persistence(inMemory: true)
    
    func loadPersistenceWithSimualtedData() {
        let viewContext = self.container.viewContext
        
        for i in 0..<7 {
            var design = DesignModel()
            design.backgroundColor = Color.random
            
            // Create a generic QREntity
            let qrEntity = QREntity(context: viewContext)
            qrEntity.id = UUID()
            qrEntity.created = Date()
            qrEntity.viewed = Date()
            qrEntity.title = "QR Code \(i)"
            qrEntity.design = try? design.asData()
            qrEntity.builder = try? BuilderModel().asData()
            
            // Create a generic TemplateEntity
            let templateEntity = TemplateEntity(context: viewContext)
            templateEntity.id = UUID()
            templateEntity.title = "Template \(i)"
            templateEntity.created = Date()
            templateEntity.viewed = Date()
            templateEntity.logo = nil
            templateEntity.design = try? design.asData()
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
#endif
}

// MARK: - Delete Functions

extension Persistence {
    
    /// Delete all entities, essentially wiping the database.
    func deleteAllEntities() throws {
        let entities = container.managedObjectModel.entities
        for entity in entities {
            try deleteEntity(entity.name!)
        }
    }
    
    /// Delete all instances of an entity in the container
    /// - Parameter entityName: The entity's name, as a String, to be deleted
    func deleteEntity(_ entityName: String) throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult>
        fetchRequest = NSFetchRequest(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try container.viewContext.execute(deleteRequest)
    }
    
}

// MARK: - Fetch Functions

extension Persistence {
    
    /// Fetch a single `QREntity` with the URI representation of its Managed Object ID.
    /// - Parameter uri: The URI representation of an NSManagedObjectID.
    /// - Returns: A `QREntity`, if one is found, else `nil`.
    func getQrEntityWithURI(_ uri: URL) -> QREntity? {
        guard let objectID = container.viewContext
            .persistentStoreCoordinator?
            .managedObjectID(forURIRepresentation: uri)
        else {
            return nil
        }
        return container.viewContext.object(with: objectID) as? QREntity
    }
    
    /// Fetch a single `TemplateEntity` with the URI representation of its Managed Object ID.
    /// - Parameter uri: The URI representation of an NSManagedObjectID.
    /// - Returns: A `TemplateEntity`, if one is found, else `nil`.
    func getTemplateEntityWithURI(_ uri: URL) -> TemplateEntity? {
        guard let objectID = container.viewContext
            .persistentStoreCoordinator?
            .managedObjectID(forURIRepresentation: uri)
        else {
            return nil
        }
        return container.viewContext.object(with: objectID) as? TemplateEntity
    }
    
    /// Fetch a single `QREntity` with its associated `UUID`.
    /// - Parameter id: A `UUID`.
    /// - Returns: A `QREntity` matching the `id`.
    func getQREntityWithUUID(_ identifier: UUID?) throws -> QREntity {
        guard let identifier = identifier else {
            logger.notice("A QREntity was requested using an invalid UUID.")
            throw PersistenceError.invalidUUID
        }
        
        let request = QREntity.fetchRequest() as NSFetchRequest<QREntity>
        request.predicate = NSPredicate(format: "%K == %@", "id", identifier as CVarArg)
        let items = try container.viewContext.fetch(request)
        
        guard let item = items.first else {
            logger.warning("No QREntity was found with provided UUID.")
            throw PersistenceError.noEntityFound
        }
        return item
    }
    
    /// Fetch a single `TemplateEntity` with its associated `UUID`.
    /// - Parameter id: A `UUID`.
    /// - Returns: A `TemplateEntity` matching the `id`.
    func getTemplateEntityWithUUID(_ identifier: UUID?) throws -> TemplateEntity {
        guard let identifier = identifier else {
            logger.notice("A TemplateEntity was requested using an invalid UUID.")
            throw PersistenceError.invalidUUID
        }
        
        let request = TemplateEntity.fetchRequest() as NSFetchRequest<TemplateEntity>
        request.predicate = NSPredicate(format: "%K == %@", "id", identifier as CVarArg)
        let items = try container.viewContext.fetch(request)
        
        guard let item = items.first else {
            logger.warning("No TemplateEntity was entity found with provided UUID.")
            throw PersistenceError.noEntityFound
        }
        return item
    }
    
    /// Fetch all `QREntity` objects matching an array of `UUID`s.
    /// - Parameter identifiers: An array of `UUID`s.
    /// - Returns: An array of `QREntity`s.
    /// - Warning: Invalid UUIDs are silently skipped. If no entities are found, an empty array is returned.
    func getQREntitiesWithUUIDs(_ identifiers: [UUID]) -> [QREntity] {
        var resultArray: [QREntity] = []
        identifiers.forEach { id in
            if let entity = try? getQREntityWithUUID(id) {
                resultArray.append(entity)
            }
        }
        return resultArray
    }
    
    /// Fetch all `TemplateEntity` objects matching an array of `UUID`s.
    /// - Parameter identifiers: An array of `UUID`s.
    /// - Returns: An array of `TemplateEntity`s.
    /// - Warning: Invalid UUIDs are silently skipped. If no entities are found, an empty array is returned.
    func getTemplateEntitiesWithUUIDs(_ identifiers: [UUID]) -> [TemplateEntity] {
        var resultArray: [TemplateEntity] = []
        identifiers.forEach { id in
            if let entity = try? getTemplateEntityWithUUID(id) {
                resultArray.append(entity)
            }
        }
        return resultArray
    }
    
    /// Fetch all `QREntity` objects matching a title `String`.
    /// - Parameter title: The entity's title as a `String`.
    /// - Returns: All matching `QREntity` as an array.
    func getQREntitiesWithTitle(_ title: String) throws -> [QREntity] {
        let request = QREntity.fetchRequest()
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", title)
        let results = try container.viewContext.fetch(request)
        return results
    }
    
    /// Fetch all `TemplateEntity` objects matching a title `String`.
    /// - Parameter title: The entity's title as a `String`.
    /// - Returns: All matching `TemplateEntity` as an array.
    func getTemplateEntitiesWithTitle(_ title: String) throws -> [TemplateEntity] {
        let request = TemplateEntity.fetchRequest()
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", title)
        let results = try container.viewContext.fetch(request)
        return results
    }
    
    /// Fetch the `k` most recent `QREntity` objects stored in the database.
    ///   - k: The number of entities to fetch. Default is `1`.
    ///   - recency: An enum representing whether to fetch entities by their `created` data or `viewed` date. Default is `created`.
    /// - Returns: All matching `QREntity`s.
    func getMostRecentQREntities(_ k: Int = 1, by recency: Recency = .created) throws -> [QREntity] {
        let request = QREntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: recency.rawValue, ascending: false)]
        request.fetchLimit = k
        let items = try container.viewContext.fetch(request)
        return items
    }
    
    /// Fetch the `k` most recent `TemplateEntity` objects stored in the database.
    /// - Parameters:
    ///   - k: The number of entities to fetch. Default is `1`.
    ///   - recency: An enum representing whether to fetch entities by their `created` data or `viewed` date. Default is `created`.
    /// - Returns: All matching `TemplateEntity`s.
    func getMostRecentTemplateEntities(_ k: Int = 1, by recency: Recency = .created) throws -> [TemplateEntity] {
        let request = TemplateEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: recency.rawValue, ascending: false)]
        request.fetchLimit = k
        let items = try container.viewContext.fetch(request)
        return items
    }
    
    /// The types of date an entity can be sorted by.
    enum Recency: String {
        case created = "created"
        case viewed = "viewed"
    }
    
    /// Fetch **all** `QREntity`s stored in the database.
    /// - Returns: An array containing all `QREntity`s.
    func getAllQREntities() throws -> [QREntity] {
        let request = QREntity.fetchRequest()
        let items = try container.viewContext.fetch(request)
        return items
    }
    
    /// Fetch **all** `TemplateEntity`s stored in the database.
    /// - Returns: An array containing all `TemplateEntity`s.
    func getAllTemplateEntities() throws -> [TemplateEntity] {
        let request = TemplateEntity.fetchRequest()
        let items = try container.viewContext.fetch(request)
        return items
    }
    
    /// Fetch **all** entities stored in the database.
    /// - Returns: A tuple containing all entities stored in the database.
    func getAllEntities() throws -> (qrEntities: [QREntity], templateEntities: [TemplateEntity]) {
        var results: (qrEntities: [QREntity], templateEntities: [TemplateEntity]) = ([],[])
        let qrRequest = QREntity.fetchRequest()
        results.qrEntities = try container.viewContext.fetch(qrRequest)
        let templateRequest = TemplateEntity.fetchRequest()
        results.templateEntities = try container.viewContext.fetch(templateRequest)
        return results
    }
}

// MARK: - Shared Database URL

public extension URL {
    
    /// Returns a URL for the given app group and database pointing to the sqlite database.
    static func storeURL(for appGroup: String, databaseName: String) -> URL {
        guard let fileContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            Logger(subsystem: Constants.bundleIdentifier, category: "persistence+url")
                .critical("The shared file container could not be created.")
            fatalError("Shared file container could not be created.")
        }
        
        return fileContainer.appendingPathComponent("\(databaseName).sqlite")
    }
}

#if canImport(CoreSpotlight)
// MARK: - Spotlight Delegate

class SpotlightDelegate: NSCoreDataCoreSpotlightDelegate {
    override func domainIdentifier() -> String {
        return "shwndvs.qr-pop.archiveContent"
    }
    
    override func indexName() -> String? {
        return "qrcode-index"
    }
    
    override func attributeSet(for object: NSManagedObject)
    -> CSSearchableItemAttributeSet? {
        guard let qrEntity = object as? QREntity else {
            return nil
        }
        
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        let model = try? QRModel(withEntity: qrEntity)
        
        attributeSet.contentDescription = "\(model?.content.builder.title ?? "Generic") QR Code"
        attributeSet.kind = model?.content.builder.title
        attributeSet.displayName = model?.title ?? "Archived QR Code"
        attributeSet.userCreated = 1
        attributeSet.thumbnailData = try? model?.jpegData(for: 180)
        return attributeSet
    }
}

// MARK: - Toggle Spotlight Indexing

extension Persistence {
    
    func toggleSpotlightIndexing(enabled: Bool) {
        guard let spotlightIndexer = spotlightIndexer else { return }
        
        if enabled {
            spotlightIndexer.startSpotlightIndexing()
        } else {
            spotlightIndexer.stopSpotlightIndexing()
        }
    }
}
#endif

// MARK: - Conform to Equatable

extension FetchedResults: Equatable {
    
    /// This is an incredibly lazy extension that doesn't *actually* check if two fetch requests are equal. Instead, it merely checks if they are the same length.
    /// This is intended for usage animating custom lists of FetchResults, specifically the removal and addition of new list items.
    /// - Parameters:
    ///   - lhs: A `FetchResult` to compare
    ///   - rhs: A `FetchResult` to compare
    /// - Returns: `true` if both sides are the same length, `false` otherwise
    public static func == (lhs: FetchedResults, rhs: FetchedResults) -> Bool {
        lhs.count == rhs.count
    }
}

// MARK: - Error Handling

extension Persistence {
    
    enum PersistenceError: Error, LocalizedError {
        case invalidUUID
        case noEntityFound
        
        var errorDescription: String? {
            switch self {
            case .invalidUUID:
                return "Invalid Entity ID"
            case .noEntityFound:
                return "No Entity Found"
            }
        }
    }
}

fileprivate let logger = Logger(subsystem: Constants.bundleIdentifier, category: "persistence")
