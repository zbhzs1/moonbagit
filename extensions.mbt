///|
pub extend FormatError with Eq::{equal, not_equal}

///|
pub extend FormatError with @debug.Debug::{to_repr}

///|
pub extend Algorithm with Eq::{equal, not_equal}

///|
pub extend Algorithm with @debug.Debug::{to_repr}

///|
pub extend Declaration with Eq::{equal, not_equal}

///|
pub extend Declaration with @debug.Debug::{to_repr}

///|
pub extend Metadata with Eq::{equal, not_equal}

///|
pub extend Metadata with @debug.Debug::{to_repr}

///|
pub extend Metadata with ToJson::{to_json}

///|
pub extend Metadata with @json.FromJson::{from_json}

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
pub extend Manifest with Eq::{equal, not_equal}

///|
pub extend Manifest with @debug.Debug::{to_repr}

///|
pub extend FetchEntry with Eq::{equal, not_equal}

///|
pub extend FetchEntry with @debug.Debug::{to_repr}

///|
pub extend FetchEntry with ToJson::{to_json}

///|
pub extend FileRecord with @debug.Debug::{to_repr}

///|
pub extend FileRecord with ToJson::{to_json}

///|
pub extend FileRecord with @json.FromJson::{from_json}

///|
pub extend BagView with @debug.Debug::{to_repr}

///|
pub extend BagView with @json.FromJson::{from_json}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub extend Severity with ToJson::{to_json}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
pub extend Report with @debug.Debug::{to_repr}

///|
pub extend Report with ToJson::{to_json}

///|
pub extend MetadataRule with @debug.Debug::{to_repr}

///|
pub extend Profile with @debug.Debug::{to_repr}

///|
pub extend ProfileReport with @debug.Debug::{to_repr}

///|
pub extend ProfileReport with ToJson::{to_json}

///|
pub extend UpgradePlan with @debug.Debug::{to_repr}
