import Foundation

struct UserStatusResponse: Decodable {
  let userStatus: UserStatus?
}

struct UserStatus: Decodable {
  let email: String?
  let cascadeModelConfigData: ModelConfigData?
  let planStatus: PlanStatus?
}

struct PlanStatus: Decodable {
  let planInfo: PlanInfo?
}

struct PlanInfo: Decodable {
  let planName: String?
}

struct ModelConfigData: Decodable {
  let clientModelConfigs: [ModelConfig]?
}

struct CommandModelResponse: Decodable {
  let clientModelConfigs: [ModelConfig]?
}

struct ModelConfig: Decodable {
  let label: String
  let modelOrAlias: ModelAlias
  let quotaInfo: QuotaInfo?
}

struct ModelAlias: Decodable {
  let model: String
}

struct QuotaInfo: Decodable {
  let remainingFraction: Double?
  let resetTime: String?
}

struct AvailableModelsResponse: Decodable {
  let models: [String: AvailableModel]?
}

struct AvailableModel: Decodable {
  let displayName: String?
  let label: String?
  let isInternal: Bool?
  let quotaInfo: QuotaInfo?
}

struct LoadCodeAssistResponse: Decodable {
  let paidTier: Tier?
  let currentTier: Tier?

  struct Tier: Decodable {
    let name: String?
  }
}
