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

import CollectionLoader



struct BMORequestHelperForLoader<FetchedObject : NSManagedObject, Metadata> : RequestHelperProtocol {
	
	typealias LocalDbObject = NSManagedObject
	typealias ImportChangesProcessing = (LocalDbChanges<NSManagedObject, Metadata>, _ cancellationCheck: () throws -> Void) throws -> [FetchedObject]
	
	let loadingOperationDelegate: LoadingOperationDelegate<[FetchedObject]>
	let importChangesProcessing: ImportChangesProcessing
	
	init(loadingOperationDelegate: LoadingOperationDelegate<[FetchedObject]>, importChangesProcessing: @escaping ImportChangesProcessing) {
		self.loadingOperationDelegate = loadingOperationDelegate
		self.importChangesProcessing = importChangesProcessing
	}
	
	/* *****************************************************************
	   MARK: Request Lifecycle Part 1: Local Request to Remote Operation
	   ***************************************************************** */
	
	func onContext_localToRemote_prepareRemoteConversion(cancellationCheck throwIfCancelled: () throws -> Void) throws -> Bool {
		return true
	}
	
	func onContext_localToRemote_willGoRemote(cancellationCheck throwIfCancelled: () throws -> Void) throws {
		try loadingOperationDelegate.onContext_remoteOperationWillStart(throwIfCancelled)
	}
	
	func onContext_localToRemoteFailed(_ error: Error) {
	}
	
	/* ************************************************************
	   MARK: Request Lifecycle Part 2: Receiving the Remote Results
	   ************************************************************ */
	
	func remoteFailed(_ error: Error) {
	}
	
	/* *******************************************************************
	   MARK: Request Lifecycle Part 3: Local Db Representation to Local Db
	   ******************************************************************* */
	
	func onContext_remoteToLocal_willImportRemoteResults(cancellationCheck throwIfCancelled: () throws -> Void) throws -> Bool {
		return try loadingOperationDelegate.onContext_operationWillImportResults(throwIfCancelled)
	}
	
	func onContext_remoteToLocal_didImportRemoteResults(_ importChanges: LocalDbChanges<NSManagedObject, Metadata>, cancellationCheck throwIfCancelled: () throws -> Void) throws {
		try loadingOperationDelegate.onContext_operationDidFinishImport(importChangesProcessing(importChanges, throwIfCancelled), throwIfCancelled)
	}
	
	func onContext_remoteToLocalFailed(_ error: Error) {
	}
	
}
