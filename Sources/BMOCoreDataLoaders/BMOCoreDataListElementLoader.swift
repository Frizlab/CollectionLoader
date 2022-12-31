/*
Copyright 2022 happn

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */

import CoreData
import Foundation

import BMO
import BMOCoreData

import CollectionLoader



public final class BMOCoreDataListElementLoader<Bridge : BridgeProtocol, FetchedObject : NSManagedObject, PageInfoRetriever : PageInfoRetrieverProtocol> : CollectionLoaderHelperProtocol
where Bridge.LocalDb.DbObject == NSManagedObject/* and NOT FetchedObject */,
		Bridge.LocalDb.DbContext == NSManagedObjectContext,
		PageInfoRetriever.CompletionResults == LocalDbChanges<NSManagedObject, Bridge.Metadata>?
{
	
	public typealias LoadingOperation = RequestOperation<Bridge>
	
	public typealias PageInfo = PageInfoRetriever.PageInfo
	public typealias CompletionResults = PageInfoRetriever.CompletionResults
	public typealias PreCompletionResults = [FetchedObject]
	
	public let bridge: Bridge
	public let localDb: Bridge.LocalDb
	public let pageInfoRetriever: PageInfoRetriever
	public let resultsController: NSFetchedResultsController<FetchedObject>
	
	public let pageInfoToRequestUserInfo: (PageInfo) -> Bridge.RequestUserInfo
	
	public private(set) var listElementObjectID: NSManagedObjectID?
	
	public convenience init(
		bridge: Bridge,
		localDb: Bridge.LocalDb,
		pageInfoRetriever: PageInfoRetriever,
		listElementEntity: NSEntityDescription, listProperty: NSRelationshipDescription,
		apiOrderProperty: NSAttributeDescription, apiOrderDelta: Int = 1,
		additionalFetchRequestPredicate: NSPredicate? = nil,
		fetchRequestToBridgeRequest: (NSFetchRequest<NSManagedObject>) -> Bridge.LocalDb.DbRequest,
		pageInfoToRequestUserInfo: @escaping (PageInfo) -> Bridge.RequestUserInfo
	) throws {
		let fetchRequest = NSFetchRequest<NSManagedObject>()
		fetchRequest.entity = listElementEntity
		fetchRequest.fetchLimit = 1
		try self.init(
			bridge: bridge, localDb: localDb, pageInfoRetriever: pageInfoRetriever,
			listElementFetchRequest: fetchRequest,
			listProperty: listProperty, apiOrderProperty: apiOrderProperty, apiOrderDelta: apiOrderDelta,
			additionalFetchRequestPredicate: additionalFetchRequestPredicate,
			fetchRequestToBridgeRequest: fetchRequestToBridgeRequest,
			pageInfoToRequestUserInfo: pageInfoToRequestUserInfo
		)
	}
	
	public init<ListElementObject : NSManagedObject>(
		bridge: Bridge,
		localDb: Bridge.LocalDb,
		pageInfoRetriever: PageInfoRetriever,
		listElementFetchRequest: NSFetchRequest<ListElementObject>, listProperty: NSRelationshipDescription,
		apiOrderProperty: NSAttributeDescription, apiOrderDelta: Int = 1,
		additionalFetchRequestPredicate: NSPredicate? = nil,
		fetchRequestToBridgeRequest: (NSFetchRequest<ListElementObject>) -> Bridge.LocalDb.DbRequest,
		pageInfoToRequestUserInfo: @escaping (PageInfo) -> Bridge.RequestUserInfo
	) throws {
		assert(apiOrderDelta > 0)
		assert(listProperty.isOrdered)
		
		self.bridge = bridge
		self.localDb = localDb
		self.pageInfoRetriever = pageInfoRetriever
		self.pageInfoToRequestUserInfo = pageInfoToRequestUserInfo
		
		self.localDbRequest = fetchRequestToBridgeRequest(listElementFetchRequest)
		
		self.listProperty = listProperty
		
		self.apiOrderDelta = apiOrderDelta
		self.apiOrderProperty = apiOrderProperty
		
		var listObjectID: NSManagedObjectID?
		try localDb.context.performAndWaitRW{ listObjectID = try localDb.context.fetch(listElementFetchRequest).first?.objectID }
		self.listElementObjectID = listObjectID
		
		let fetchedResultsControllerFetchRequest = NSFetchRequest<FetchedObject>()
		fetchedResultsControllerFetchRequest.entity = listProperty.destinationEntity!
		fetchedResultsControllerFetchRequest.sortDescriptors = [NSSortDescriptor(key: apiOrderProperty.name, ascending: true)]
		if let listObjectID {
			fetchedResultsControllerFetchRequest.predicate = NSPredicate(format: "%K == %@", listProperty.inverseRelationship!.name, listObjectID)
		} else {
			/* We want to retrieve the objects whose inverse relationship name of the list property match the list element fetch request, but the list element fetch request currently matches nothing.
			 * We have to create a predicate to match anyway.
			 * Two case:
			 *   - The list element fetch request has a predicate: it should be enough to add the inverse relationship name to the key paths of the predicate.
			 *   - The list element fetch request does not have a predicate: we assume then any object of the type we want whose inverse relationship name value is not nil will match.
			 *     Indeed, if it is set, the value must be to the list element we want as there should only be one in the db… */
			fetchedResultsControllerFetchRequest.predicate = (
				listElementFetchRequest.predicate?.predicateByAddingKeyPathPrefix(listProperty.inverseRelationship!.name) ??
				NSPredicate(format: "%K != NULL", listProperty.inverseRelationship!.name)
			)
		}
		if let additionalFetchRequestPredicate, let fPredicate = fetchedResultsControllerFetchRequest.predicate {fetchedResultsControllerFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fPredicate, additionalFetchRequestPredicate])}
		else if let additionalFetchRequestPredicate                                                             {fetchedResultsControllerFetchRequest.predicate = additionalFetchRequestPredicate}
		self.resultsController = NSFetchedResultsController<FetchedObject>(fetchRequest: fetchedResultsControllerFetchRequest, managedObjectContext: localDb.context, sectionNameKeyPath: nil, cacheName: nil)
		
		try resultsController.performFetch()
	}
	
	/* *************************
	   MARK: Get Current Objects
	   ************************* */
	
	public func onContext_numberOfObjects() -> Int {
		return resultsController.fetchedObjects!.count
	}
	
	public func onContext_object(at index: Int) -> FetchedObject {
		return resultsController.fetchedObjects![index]
	}
	
	/* *********************************************
	   MARK: Get Objects from Pre-Completion Results
	   ********************************************* */
	
	public func onContext_numberOfObjects(from preCompletionResults: PreCompletionResults) -> Int {
		return preCompletionResults.count
	}
	
	public func onContext_object(at index: Int, from preCompletionResults: PreCompletionResults) -> FetchedObject {
		return preCompletionResults[index]
	}
	
	/* ****************
	   MARK: Load Pages
	   **************** */
	
	public func operationForLoading(pageInfo: PageInfo, delegate: LoadingOperationDelegate<PreCompletionResults>) throws -> LoadingOperation {
#warning("TODO: apiOrderProperty (requires the start offset of the page info…)")
		let helper = BMORequestHelperForLoader<FetchedObject, Bridge.Metadata>(
			loadingOperationDelegate: delegate,
			importChangesProcessing: { changes, throwIfCancelled in
				/* We only want objects of the correct type in the pre-completion results. */
				try changes.importedObjects.compactMap{
					try throwIfCancelled()
					return $0.object as? FetchedObject
				}
			}
		)
		let helpers = RequestHelperCollectionForOldRuntimes(helper)
		let request = Request(localDb: localDb, localRequest: localDbRequest, remoteUserInfo: pageInfoToRequestUserInfo(pageInfo))
		return RequestOperation(bridge: bridge, request: request, additionalHelpers: helpers, remoteOperationQueue: OperationQueue(), computeOperationQueue: OperationQueue())
	}
	
	public func results(from finishedLoadingOperation: LoadingOperation) -> Result<CompletionResults, Error> {
		return finishedLoadingOperation.result.map{ $0.dbChanges }
	}
	
	/* *************************
	   MARK: Getting Pages Infos
	   ************************* */
	
	public func initialPageInfo() -> PageInfo {
		return pageInfoRetriever.initialPageInfo()
	}
	
	public func nextPageInfo(for completionResults: LocalDbChanges<NSManagedObject, Bridge.Metadata>?, from pageInfo: PageInfo) -> PageInfo? {
		return pageInfoRetriever.nextPageInfo(for: completionResults, from: pageInfo)
	}
	
	public func previousPageInfo(for completionResults: LocalDbChanges<NSManagedObject, Bridge.Metadata>?, from pageInfo: PageInfo) -> PageInfo? {
		return pageInfoRetriever.previousPageInfo(for: completionResults, from: pageInfo)
	}
	
	/* **********************
	   MARK: Deleting Objects
	   ********************** */
	
	public func onContext_delete(object: FetchedObject) {
		object.setValue(nil, forKey: listProperty.inverseRelationship!.name)
	}
	
	/* ***************
	   MARK: - Private
	   *************** */
	
	private let localDbRequest: Bridge.LocalDb.DbRequest
	
	private let listProperty: NSRelationshipDescription
	
	private let apiOrderProperty: NSAttributeDescription
	private let apiOrderDelta: Int /* Must be > 0 */
	
}
