import { ClaudeProvider } from './claude-provider';
import { ClaudeConfig, ClaudeModels, ModelRoutingStrategy } from './types';

/**
 * Factory function to create a Claude provider instance
 */
export function createClaudeProvider(config: Partial<ClaudeConfig>): ClaudeProvider {
  if (!config.apiKey) {
    // Try to get from environment
    const envApiKey = process.env.ANTHROPIC_API_KEY || process.env.CLAUDE_API_KEY;
    
    if (!envApiKey) {
      throw new Error(
        'Anthropic API key is required. Provide it in config or set ANTHROPIC_API_KEY environment variable.'
      );
    }
    
    config.apiKey = envApiKey;
  }

  // Set defaults
  const fullConfig: ClaudeConfig = {
    provider: 'claude',
    apiKey: config.apiKey,
    model: config.model || ClaudeModels.CLAUDE_3_5_SONNET,
    routingStrategy: config.routingStrategy || ModelRoutingStrategy.AUTO,
    maxTokens: config.maxTokens || 4096,
    temperature: config.temperature ?? 0.7,
    enableStreaming: config.enableStreaming ?? true,
    enableToolUse: config.enableToolUse ?? true,
    enableImageInput: config.enableImageInput ?? true,
    enableDocumentParsing: config.enableDocumentParsing ?? true,
    usageTracking: config.usageTracking ?? true,
    auditLogging: config.auditLogging ?? false,
    cache: config.cache ?? { enabled: true, ttlSeconds: 3600, maxEntries: 100 },
    extendedThinking: config.extendedThinking ?? { enabled: false },
    timeout: config.timeout || 60000,
    maxRetries: config.maxRetries || 3,
    ...config,
  };

  return new ClaudeProvider(fullConfig);
}

/**
 * Create a provider optimized for coding tasks
 */
export function createCodingProvider(config: Partial<ClaudeConfig> = {}): ClaudeProvider {
  return createClaudeProvider({
    ...config,
    model: config.model || ClaudeModels.CLAUDE_3_5_SONNET,
    routingStrategy: config.routingStrategy || ModelRoutingStrategy.BALANCED,
    temperature: config.temperature ?? 0.3, // Lower temperature for more deterministic code
  });
}

/**
 * Create a provider optimized for reasoning tasks
 */
export function createReasoningProvider(config: Partial<ClaudeConfig> = {}): ClaudeProvider {
  return createClaudeProvider({
    ...config,
    model: config.model || ClaudeModels.CLAUDE_3_7_SONNET,
    routingStrategy: config.routingStrategy || ModelRoutingStrategy.PERFORMANCE,
    extendedThinking: {
      enabled: true,
      budgetTokens: config.extendedThinking?.budgetTokens || 16000,
      includeInResponse: false,
    },
  });
}

/**
 * Create a cost-effective provider for simple tasks
 */
export function createEconomyProvider(config: Partial<ClaudeConfig> = {}): ClaudeProvider {
  return createClaudeProvider({
    ...config,
    model: config.model || ClaudeModels.CLAUDE_HAIKU_3_5,
    routingStrategy: config.routingStrategy || ModelRoutingStrategy.ECONOMY,
    cache: {
      enabled: true,
      ttlSeconds: 7200, // Longer cache for economy
      maxEntries: 500,
    },
  });
}

/**
 * Create an enterprise provider with audit logging
 */
export function createEnterpriseProvider(
  config: Partial<ClaudeConfig> & { teamId: string }
): ClaudeProvider {
  return createClaudeProvider({
    ...config,
    teamId: config.teamId,
    auditLogging: true,
    usageTracking: true,
    cache: config.cache ?? { enabled: true, ttlSeconds: 1800 },
  });
}
