@preconcurrency package import AWSDynamoDB
package import Logging

package func createJournalTable(
    logger: Logger, client: DynamoDBClient, tableName: String, gsiName: String
) async throws {
    let output = try await client.listTables(input: .init())
    logger.debug("createJournalTable DynamoDB list tables: \(output)")
    let tableNames = output.tableNames ?? []

    if tableNames.contains(tableName) {
        logger.info("createJournalTable Journal Table skipped")
    } else {
        let output = try await client.createTable(
            input: .init(
                attributeDefinitions: [
                    .init(attributeName: "pkey", attributeType: .s),
                    .init(attributeName: "skey", attributeType: .s),
                    .init(attributeName: "aid", attributeType: .s),
                    .init(attributeName: "seq_nr", attributeType: .n),
                ],
                globalSecondaryIndexes: [
                    .init(
                        indexName: gsiName,
                        keySchema: [
                            .init(attributeName: "aid", keyType: .hash),
                            .init(attributeName: "seq_nr", keyType: .range),
                        ],
                        projection: .init(projectionType: .all),
                        provisionedThroughput: .init(readCapacityUnits: 10, writeCapacityUnits: 5)
                    )
                ],
                keySchema: [
                    .init(attributeName: "pkey", keyType: .hash),
                    .init(attributeName: "skey", keyType: .range),
                ],
                provisionedThroughput: .init(readCapacityUnits: 10, writeCapacityUnits: 5),
                tableName: tableName
            )
        )
        logger.debug("createJournalTable Journal create table: \(output)")
        logger.info("createJournalTable Journal Table finished")
    }
}

package func createSnapshotTable(
    logger: Logger, client: DynamoDBClient, tableName: String, gsiName: String
) async throws {
    let output = try await client.listTables(input: .init())
    logger.debug("createSnapshotTable DynamoDB list tables: \(output)")
    let tableNames = output.tableNames ?? []

    if tableNames.contains(tableName) {
        logger.info("createSnapshotTable Snapshot Table skipped")
    } else {
        let output = try await client.createTable(
            input: .init(
                attributeDefinitions: [
                    .init(attributeName: "pkey", attributeType: .s),
                    .init(attributeName: "skey", attributeType: .s),
                    .init(attributeName: "aid", attributeType: .s),
                    .init(attributeName: "seq_nr", attributeType: .n),
                ],
                globalSecondaryIndexes: [
                    .init(
                        indexName: gsiName,
                        keySchema: [
                            .init(attributeName: "aid", keyType: .hash),
                            .init(attributeName: "seq_nr", keyType: .range),
                        ],
                        projection: .init(projectionType: .all),
                        provisionedThroughput: .init(readCapacityUnits: 10, writeCapacityUnits: 5)
                    )
                ],
                keySchema: [
                    .init(attributeName: "pkey", keyType: .hash),
                    .init(attributeName: "skey", keyType: .range),
                ],
                provisionedThroughput: .init(readCapacityUnits: 10, writeCapacityUnits: 5),
                tableName: tableName
            )
        )
        logger.debug("createSnapshotTable Snapshot create table: \(output)")
    }
}

package func waitTable(client: DynamoDBClient, targetTableName: String) async throws -> Bool {
    (try await client.listTables(input: .init())).tableNames?.contains(targetTableName) == true
}
