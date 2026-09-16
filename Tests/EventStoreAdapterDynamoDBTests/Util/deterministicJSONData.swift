import Foundation

func deterministicJSONData(_ value: some Encodable) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting.insert(.sortedKeys)
  return try encoder.encode(value)
}
