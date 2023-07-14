/*
Copyright 2023 happn

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



internal final class BlockCollectionLoaderDelegate<CollectionLoaderHelper : CollectionLoaderHelperProtocol> : CollectionLoaderDelegate {
	
	let willStartLoading: @MainActor (CLDPageLoadDescription) -> Void
	let didFinishLoading: @MainActor (CLDPageLoadDescription, Result<CompletionResults, Error>) -> Void
	let canDelete: (FetchedObject) -> Bool
	let willFinishLoading: (CLDPageLoadDescription, PreCompletionResults, () throws -> Void) throws -> Void
	
	init(
		willStartLoading: @escaping (CLDPageLoadDescription) -> Void,
		didFinishLoading: @escaping (CLDPageLoadDescription, Result<CompletionResults, Error>) -> Void,
		canDelete: @escaping (FetchedObject) -> Bool,
		willFinishLoading: @escaping (CLDPageLoadDescription, PreCompletionResults, () throws -> Void) throws -> Void
	) {
		self.willStartLoading = willStartLoading
		self.didFinishLoading = didFinishLoading
		self.canDelete = canDelete
		self.willFinishLoading = willFinishLoading
	}
	
	@MainActor
	func willStartLoading(pageLoadDescription: CLDPageLoadDescription) {
		willStartLoading(pageLoadDescription)
	}
	
	@MainActor
	func didFinishLoading(pageLoadDescription: CLDPageLoadDescription, results: Result<CompletionResults, Error>) {
		didFinishLoading(pageLoadDescription, results)
	}
	
	func onContext_canDelete(object: FetchedObject) -> Bool {
		return canDelete(object)
	}
	
	func onContext_willFinishLoading(pageLoadDescription: CLDPageLoadDescription, results: PreCompletionResults, cancellationCheck throwIfCancelled: () throws -> Void) throws {
		try willFinishLoading(pageLoadDescription, results, throwIfCancelled)
	}
	
}
