import FirestoreOperations

/// CLI-facing name for the shared operation error. ArgumentParser prints
/// `description` and exits with code 1.
typealias CLIError = FirestoreOperationError
