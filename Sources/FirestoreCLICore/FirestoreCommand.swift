import ArgumentParser

public enum FirestoreCLIInfo {
  public static let version = "0.1.0"
}

public struct FirestoreCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "frd",
    abstract: "Read and write Cloud Firestore documents through the REST API.",
    discussion: """
    Credentials are resolved in this order:
      --token, FIRESTORE_ACCESS_TOKEN, GOOGLE_OAUTH_ACCESS_TOKEN,
      --token-file, --service-account / GOOGLE_APPLICATION_CREDENTIALS,
      --api-key, FIRESTORE_API_KEY, GOOGLE_API_KEY.

    The project defaults to FIRESTORE_PROJECT_ID, GOOGLE_CLOUD_PROJECT,
    GCLOUD_PROJECT, then the service account's project_id. The database
    defaults to FIRESTORE_DATABASE_ID, then "(default)".

    Examples:
      # Access token (flag or environment)
      frd get users/alice --project my-project --token "$TOKEN"
      # OR
      export FIRESTORE_PROJECT_ID=my-project
      export FIRESTORE_ACCESS_TOKEN="$(gcloud auth print-access-token)"
      frd get users/alice

      # Token file
      frd get users/alice --project my-project --token-file ~/.frd-token

      # Service account (mints and refreshes access tokens)
      frd get users/alice --project my-project --service-account key.json
      # OR
      export GOOGLE_APPLICATION_CREDENTIALS=~/keys/service-account.json
      frd get users/alice --project my-project

      # API key
      frd get users/alice --project my-project --api-key "$API_KEY"

      # Firestore emulator
      frd get users/alice --project demo --emulator-host localhost:8080

      # Write from stdin
      echo '{"name":"Alice"}' | frd set users/alice --project my-project --merge
    """,
    version: FirestoreCLIInfo.version,
    subcommands: [
      GetCommand.self,
      ListCommand.self,
      CollectionsCommand.self,
      SetCommand.self,
      UpdateCommand.self,
      DeleteCommand.self,
      BatchGetCommand.self,
      BatchWriteCommand.self,
    ]
  )

  public init() {}
}
