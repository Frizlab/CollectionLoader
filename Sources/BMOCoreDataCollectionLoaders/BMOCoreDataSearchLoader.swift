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



public final class BMOCoreDataSearchLoader<Bridge : BridgeProtocol, FetchedObject : NSManagedObject, PageInfoRetriever : PageInfoRetrieverProtocol> : CollectionLoaderHelperProtocol
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
	
	public init(
		bridge: Bridge,
		localDb: Bridge.LocalDb,
		pageInfoRetriever: PageInfoRetriever,
		fetchRequest: NSFetchRequest<FetchedObject>,
		deletionDateProperty: NSAttributeDescription? = nil,
		apiOrderProperty: NSAttributeDescription? = nil,
		apiOrderDelta: Int = 1,
		fetchRequestToBridgeRequest: (NSFetchRequest<FetchedObject>) -> Bridge.LocalDb.DbRequest,
		pageInfoToRequestUserInfo: @escaping (PageInfo) -> Bridge.RequestUserInfo
	) throws {
		assert(apiOrderDelta > 0)
		assert(deletionDateProperty.flatMap{ ["NSDate", "Date"].contains($0.attributeValueClassName) } ?? true)
		
		let controllerFetchRequest = fetchRequest.copy() as! NSFetchRequest<FetchedObject> /* We must copy because of ObjC legacy. */
		if let apiOrderProperty {
			controllerFetchRequest.sortDescriptors = [NSSortDescriptor(key: apiOrderProperty.name, ascending: true)] + (controllerFetchRequest.sortDescriptors ?? [])
		}
		if let deletionDateProperty {
			let deletionPredicate = NSPredicate(format: "%K == NULL", deletionDateProperty.name)
			if let currentPredicate = controllerFetchRequest.predicate {controllerFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [currentPredicate, deletionPredicate])}
			else                                                       {controllerFetchRequest.predicate = deletionPredicate}
		}
		
		self.bridge = bridge
		self.localDb = localDb
		self.pageInfoRetriever = pageInfoRetriever
		self.pageInfoToRequestUserInfo = pageInfoToRequestUserInfo
		self.localDbRequest = fetchRequestToBridgeRequest(fetchRequest)
		self.resultsController = NSFetchedResultsController<FetchedObject>(fetchRequest: controllerFetchRequest, managedObjectContext: localDb.context, sectionNameKeyPath: nil, cacheName: nil)
		
		self.apiOrderDelta = apiOrderDelta
		self.apiOrderProperty = apiOrderProperty
		self.deletionDateProperty = deletionDateProperty
		
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
		if let deletionDateProperty {object.setValue(Date(), forKey: deletionDateProperty.name)}
		else                        {localDb.context.delete(object)}
	}
	
	/* ***************
	   MARK: - Private
	   *************** */
	
	private let localDbRequest: Bridge.LocalDb.DbRequest
	
	private let deletionDateProperty: NSAttributeDescription?
	private let apiOrderProperty: NSAttributeDescription?
	private let apiOrderDelta: Int /* Must be > 0 */
	
}
