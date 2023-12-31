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



public enum ConcurrentLoadBehavior {
	
	/** Queue the new load after all the queued loadings. */
	case queue
	/** Cancel all queued loadings except current and add new loading to the queue. */
	case replaceQueue
	/** Cancel all the queue, including the current one and add new loading to the queue. */
	case cancelAllOther
	
	/** Skip this load if there is one already queued or in progress. */
	case skip
	/** Skip this load if there is one exactly the same reason queued or in progress. */
	case skipSame
	/** Skip this load if there is one for the same reason queued or in progress. */
	case skipSameReason
	/** Skip this load if there is one for the same page info queued or in progress. */
	case skipSamePageInfo
	
}
