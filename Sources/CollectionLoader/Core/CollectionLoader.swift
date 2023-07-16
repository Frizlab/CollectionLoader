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

import Foundation



/**
 Load a collection with a helper.
 
 The collection loader does not actually load anything: the operation returned by the collection loader helper do.
 
 The collection loader will simply define a context in which loading pages is easier.
 In particular, it will properly “erase” the object not in the page when loading the first page.
 A “sync” algorithm also exists (not implemented) to load a collection range and have the proper objects removed automatically if possible.
 
 - Note: A loading collection loader **and its delegate** are strongly retained while a page load is in progress.
 Cancelling all loadings is possible. */
@MainActor
public final class CollectionLoader<Helper : CollectionLoaderHelperProtocol> {
	
	public typealias PageInfo = Helper.PageInfo
	public typealias CLPageLoadDescription = PageLoadDescription<PageInfo>
	
	public let helper: Helper
	/**
	 The queue on which the loading operations are launched.
	 There are no restrictions on the `maxConcurrentOperationCount` of the queue. */
	public let operationQueue: OperationQueue
	
	public private(set) var nextPageInfo:     PageInfo?
	public private(set) var previousPageInfo: PageInfo?
	
	public var currentPageLoad: CLPageLoadDescription? {
		currentOperation?.pageLoadDescription
	}
	
	public weak var delegate: (any CollectionLoaderDelegate<Helper>)? {
		didSet {blockDelegate = nil}
	}
	
	public init(helper: Helper, operationQueue: OperationQueue = OperationQueue()) {
		self.helper = helper
		self.operationQueue = operationQueue
	}
	
	public func setDelegateWithBlocks(
		willStartLoading: @escaping @MainActor (CLPageLoadDescription) -> Void = { _ in },
		didFinishLoading: @escaping @MainActor (CLPageLoadDescription, Result<Helper.CompletionResults, Error>) -> Void = { _, _ in },
		canDelete: @escaping (Helper.FetchedObject) -> Bool = { _ in true },
		willFinishLoading: @escaping (CLPageLoadDescription, Helper.PreCompletionResults, () throws -> Void) throws -> Void = { _, _, _ in }
	) {
		let newDelegate = BlockCollectionLoaderDelegate<Helper>(
			willStartLoading: willStartLoading, didFinishLoading: didFinishLoading,
			canDelete: canDelete, willFinishLoading: willFinishLoading
		)
		/* Note: The blockDelegate variable must be set AFTER setting the delegate (the delegate set resets the block delegate to `nil`). */
		delegate = newDelegate
		blockDelegate = newDelegate
	}
	
	/**
	 Loads the initial page; the one when no page info is known, or when a complete reload is wanted.
	 
	 We did not name this `loadFirstPage` because if the collection is bidirectional, the initial page might not be the first. */
	public func loadInitialPage() {
		let pld = CLPageLoadDescription(loadedPage: helper.initialPageInfo(), loadingReason: .initialPage)
		load(pageLoadDescription: pld, concurrentLoadBehavior: .cancelAllOther)
	}
	
	public func loadNextPage() {
		guard let nextPageInfo else {return}
		let pld = CLPageLoadDescription(loadedPage: nextPageInfo, loadingReason: .nextPage)
		load(pageLoadDescription: pld, concurrentLoadBehavior: .skipSameReason)
	}
	
	public func loadPreviousPage() {
		guard let previousPageInfo else {return}
		let pld = CLPageLoadDescription(loadedPage: previousPageInfo, loadingReason: .previousPage)
		load(pageLoadDescription: pld, concurrentLoadBehavior: .skipSameReason)
	}
	
	public func cancelAllLoadings() {
		currentOperation?.cancel()
		pendingOperations.forEach{ $0.cancel() }
	}
	
	/**
	 Only one page load at a time is allowed.
	 When a loading operations is added to the queue, it is made dependent on the latest loading operation added. */
	public func load(pageLoadDescription: CLPageLoadDescription, concurrentLoadBehavior: ConcurrentLoadBehavior = .queue, customOperationDependencies: [Operation] = []) {
		/* We capture the delegate and the helper so we always get the same one for all the callbacks. */
		let helper = helper
		let delegate = delegate
		
		switch concurrentLoadBehavior {
			case .queue:          (/*nop*/)
			case .replaceQueue:   pendingOperations.forEach{ $0.cancel() }
			case .cancelAllOther: pendingOperations.forEach{ $0.cancel() }; currentOperation?.cancel()
				
			case .skip:             guard  ([currentOperation].compactMap{ $0 } + pendingOperations).isEmpty else {return}
			case .skipSame:         guard !([currentOperation].compactMap{ $0 } + pendingOperations).contains(where: { $0.pageLoadDescription == pageLoadDescription }) else {return}
			case .skipSameReason:   guard !([currentOperation].compactMap{ $0 } + pendingOperations).contains(where: { $0.pageLoadDescription.loadingReason == pageLoadDescription.loadingReason }) else {return}
			case .skipSamePageInfo: guard !([currentOperation].compactMap{ $0 } + pendingOperations).contains(where: { $0.pageLoadDescription.loadedPage == pageLoadDescription.loadedPage }) else {return}
		}
		
		let operation: Helper.LoadingOperation
		let loadingDelegate = pageLoadDescription.operationLoadingDelegate(with: helper, pageLoadDescription: pageLoadDescription, delegate: delegate)
		do    {operation = try helper.operationForLoading(pageInfo: pageLoadDescription.loadedPage, delegate: loadingDelegate)}
		catch {Self.callDidFinishLoading(on: delegate, pageLoadDescription: pageLoadDescription, results: .failure(error)); return}
		
		/* Yes, self is strongly captured, on purpose. */
		let prestart = BlockOperation{
			/* On main queue (and thus on main actor/thread). */
			/* Let’s call the delegate first. */
			Self.callWillStartLoading(on: delegate, pageLoadDescription: pageLoadDescription)
			
			/* Then we remove ourselves from the pending operations and put ourselves as the current operation instead.
			 * By construction, our operation is the first one of the pending operations. */
			assert(self.currentOperation == nil)
			self.currentOperation = self.pendingOperations.removeFirst() /* Crashes if pendingOperations is empty, which is what we want. */
		}
		/* Yes, self is strongly captured, on purpose. */
		let completion = BlockOperation{
			/* On main queue (and thus on main actor/thread). */
			/* First, we’ll check for the previous/next page info depending on the loading reason. */
			let loadingOperationResults = helper.results(from: operation)
			switch pageLoadDescription.loadingReason {
				case .initialPage:
					/* We set both the previous and next page. */
					if let loadingOperationSuccess = try? loadingOperationResults.get() {
						self.nextPageInfo     = helper.nextPageInfo(    for: loadingOperationSuccess, from: pageLoadDescription.loadedPage)
						self.previousPageInfo = helper.previousPageInfo(for: loadingOperationSuccess, from: pageLoadDescription.loadedPage)
					}
					
				case .nextPage:
					if let loadingOperationSuccess = try? loadingOperationResults.get() {
						self.nextPageInfo = helper.nextPageInfo(for: loadingOperationSuccess, from: pageLoadDescription.loadedPage)
					}
					
				case .previousPage:
					if let loadingOperationSuccess = try? loadingOperationResults.get() {
						self.previousPageInfo = helper.previousPageInfo(for: loadingOperationSuccess, from: pageLoadDescription.loadedPage)
					}
					
				case .sync:
					(/*nop*/)
			}
			
			/* Then we remove ourselves as the current operation. */
			self.currentOperation = nil
			
			/* And finally, we call the delegate. */
			Self.callDidFinishLoading(on: delegate, pageLoadDescription: pageLoadDescription, results: loadingOperationResults)
		}
		
		let loadingOperations = LoadingOperations(prestart: prestart, loading: operation, completion: completion, pageLoadDescription: pageLoadDescription)
		loadingOperations.setupDependencies(previousOperations: pendingOperations.last ?? currentOperation)
		loadingOperations.prestart.addDependencies(customOperationDependencies)
		pendingOperations.append(loadingOperations)
		
		operationQueue.addOperations([operation], waitUntilFinished: false)
		OperationQueue.main.addOperations([prestart, completion], waitUntilFinished: false)
	}
	
	/* ***************
	   MARK: - Private
	   *************** */
	
	/* No lock for either vars, because only accessed/modified on main actor. */
	private var currentOperation: LoadingOperations?
	private var pendingOperations = [LoadingOperations]()
	
	/* We keep a strong reference to the block delegate when the user sets it. */
	private var blockDelegate: BlockCollectionLoaderDelegate<Helper>?
	
	@MainActor
	private struct LoadingOperations {
		
		let prestart:   Operation
		let loading:    Operation
		let completion: Operation
		
		let pageLoadDescription: CLPageLoadDescription
		
		func setupDependencies(previousOperations: LoadingOperations?) {
			if let previousOperations {
				/* The new loading can only be started if all the previously launched loadings are finished (either by truly finished or by being cancelled).
				 * As this is true for all loadings, adding a dependency only on the completion of the previous loading is enough. */
				prestart.addDependency(previousOperations.completion)
			}
			loading.addDependency(prestart)
			completion.addDependency(loading)
		}
		
		func cancel() {
			/* We do NOT cancel the prestart and completion operations.
			 * If we did, we could get missing notifications in the delegate, which we want to avoid.
			 *
			 * This would happen because
			 *   1/ cancelled operation’s dependencies are ignored and
			 *   2/ the start() method finishes the operation without even launching it for most operations
			 *       (tested for a block operation: if it is cancelled when added in the queue, the block will not run).
			 *
			 * So for instance if the prestart operation has run but the loading operation is still in progress while a group is cancelled,
			 *  the completion operation would be completely skipped and the delegate would not be called. */
			loading.cancel()
		}
		
	}
	
}


/* Extension to “unerase” the delegate.
 * Maybe some day in a future version of Swift these will not be required. */
private extension CollectionLoader {
	
	private static func callWillStartLoading(on delegate: (any CollectionLoaderDelegate<Helper>)?, pageLoadDescription: CLPageLoadDescription) {
		if let delegate {
			callWillStartLoading(onNonOptional: delegate, pageLoadDescription: pageLoadDescription)
		}
	}
	private static func callWillStartLoading<Delegate : CollectionLoaderDelegate>(onNonOptional delegate: Delegate, pageLoadDescription: CLPageLoadDescription)
	where Delegate.CollectionLoaderHelper == Helper {
		delegate.willStartLoading(pageLoadDescription: pageLoadDescription)
	}
	
	private static func callDidFinishLoading(on delegate: (any CollectionLoaderDelegate<Helper>)?, pageLoadDescription: CLPageLoadDescription, results: Result<Helper.CompletionResults, Error>) {
		if let delegate {
			callDidFinishLoading(onNonOptional: delegate, pageLoadDescription: pageLoadDescription, results: results)
		}
	}
	private static func callDidFinishLoading<Delegate : CollectionLoaderDelegate>(onNonOptional delegate: Delegate, pageLoadDescription: CLPageLoadDescription, results: Result<Helper.CompletionResults, Error>)
	where Delegate.CollectionLoaderHelper == Helper {
		delegate.didFinishLoading(pageLoadDescription: pageLoadDescription, results: results)
	}
	
}
