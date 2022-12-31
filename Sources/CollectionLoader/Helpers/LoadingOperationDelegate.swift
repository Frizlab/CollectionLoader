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



public struct LoadingOperationDelegate<PreCompletionResults> {
	
	/* BMO: onContext_localToRemote_willGoRemote */
	public var onContext_remoteOperationWillStart: (() throws -> Void) throws -> Void
	
	/* BMO: onContext_remoteToLocal_willImportRemoteResults */
	/**
	 If this returns `false`, the remote operation results should _not_ be imported, but the loading operation should finish successfully.
	 If this throws, the import should not be attempted and the loading operation should fail. */
	public var onContext_operationWillImportResults: (() throws -> Void) throws -> Bool
	
	/* BMO: onContext_remoteToLocal_didImportRemoteResults */
	/**
	 This must be called just after the import has finished, while still on the db context.
	 If this throws, the loading operation should fail. */
	public var onContext_operationDidFinishImport: (PreCompletionResults, () throws -> Void) throws -> Void
	
	public init(
		willStart: @escaping (() throws -> Void) throws -> Void = { _ in },
		willImport: @escaping (() throws -> Void) throws -> Bool = { _ in true },
		didFinishImport: @escaping (PreCompletionResults, () throws -> Void) throws -> Void = { _, _ in }
	) {
		self.onContext_remoteOperationWillStart = willStart
		self.onContext_operationWillImportResults = willImport
		self.onContext_operationDidFinishImport = didFinishImport
	}
	
}
