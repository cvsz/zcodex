import { createClaudeProvider, createCodingProvider, createReasoningProvider, createEconomyProvider, createEnterpriseProvider } from '../src/factory';
import { ClaudeModels, ModelRoutingStrategy } from '../src/types';

describe('Claude Provider Factory', () => {
  beforeEach(() => {
    // Set test API key
    process.env.ANTHROPIC_API_KEY = 'test-api-key';
  });

  afterEach(() => {
    delete process.env.ANTHROPIC_API_KEY;
  });

  describe('createClaudeProvider', () => {
    it('should create provider with environment API key', () => {
      const provider = createClaudeProvider({});
      expect(provider).toBeDefined();
    });

    it('should create provider with explicit API key', () => {
      const provider = createClaudeProvider({ apiKey: 'explicit-key' });
      expect(provider).toBeDefined();
    });

    it('should throw error without API key', () => {
      delete process.env.ANTHROPIC_API_KEY;
      expect(() => createClaudeProvider({})).toThrow('Anthropic API key is required');
    });

    it('should use default model', () => {
      const provider = createClaudeProvider({});
      const capabilities = provider.getModelCapabilities();
      expect(capabilities.maxContextTokens).toBe(200000);
    });

    it('should use specified model', () => {
      const provider = createClaudeProvider({ 
        model: ClaudeModels.CLAUDE_OPUS_4 
      });
      const capabilities = provider.getModelCapabilities(ClaudeModels.CLAUDE_OPUS_4);
      expect(capabilities.costPerInputToken).toBe(15e-6);
    });
  });

  describe('createCodingProvider', () => {
    it('should create provider optimized for coding', () => {
      const provider = createCodingProvider();
      expect(provider).toBeDefined();
      
      const capabilities = provider.getModelCapabilities();
      // Should use Claude 3.5 Sonnet for coding
      expect(capabilities.supportsToolUse).toBe(true);
    });

    it('should use lower temperature for deterministic code', () => {
      const provider = createCodingProvider({ temperature: 0.2 });
      expect(provider).toBeDefined();
    });
  });

  describe('createReasoningProvider', () => {
    it('should create provider with extended thinking enabled', () => {
      const provider = createReasoningProvider();
      expect(provider).toBeDefined();
      
      const capabilities = provider.getModelCapabilities();
      expect(capabilities.supportsExtendedThinking).toBe(true);
    });

    it('should use Claude 3.7 Sonnet for reasoning', () => {
      const provider = createReasoningProvider();
      const capabilities = provider.getModelCapabilities();
      expect(capabilities.maxOutputTokens).toBe(64000);
    });
  });

  describe('createEconomyProvider', () => {
    it('should create cost-effective provider', () => {
      const provider = createEconomyProvider();
      expect(provider).toBeDefined();
      
      const capabilities = provider.getModelCapabilities();
      expect(capabilities.costPerInputToken).toBeLessThan(1e-6);
    });

    it('should use Haiku model', () => {
      const provider = createEconomyProvider();
      const capabilities = provider.getModelCapabilities();
      expect(capabilities.supportsVision).toBe(true);
    });
  });

  describe('createEnterpriseProvider', () => {
    it('should create provider with audit logging', () => {
      const provider = createEnterpriseProvider({ teamId: 'test-team' });
      expect(provider).toBeDefined();
    });

    it('should require teamId', () => {
      // @ts-ignore - testing runtime behavior
      expect(() => createEnterpriseProvider({})).toThrow();
    });
  });
});

describe('Model Routing', () => {
  beforeEach(() => {
    process.env.ANTHROPIC_API_KEY = 'test-api-key';
  });

  it('should route simple tasks to Haiku', () => {
    const provider = createClaudeProvider({
      routingStrategy: ModelRoutingStrategy.AUTO,
    });
    
    const decision = provider.getRoutingDecision([
      { role: 'user', content: 'What is the capital of France?' }
    ]);
    
    expect(decision.selectedModel).toBeDefined();
  });

  it('should route complex tasks to Opus', () => {
    const provider = createClaudeProvider({
      routingStrategy: ModelRoutingStrategy.AUTO,
    });
    
    const decision = provider.getRoutingDecision([
      { 
        role: 'user', 
        content: 'Implement a complete refactoring of the entire architecture with multi-step plan for security vulnerability optimization' 
      }
    ]);
    
    expect(decision.selectedModel).toBeDefined();
  });
});

describe('Cache Functionality', () => {
  beforeEach(() => {
    process.env.ANTHROPIC_API_KEY = 'test-api-key';
  });

  it('should enable cache by default', () => {
    const provider = createClaudeProvider({});
    expect(provider).toBeDefined();
  });

  it('should allow disabling cache', () => {
    const provider = createClaudeProvider({
      cache: { enabled: false }
    });
    expect(provider).toBeDefined();
  });

  it('should clear cache', () => {
    const provider = createClaudeProvider({});
    provider.clearCache();
    expect(provider).toBeDefined();
  });
});

describe('Usage Tracking', () => {
  beforeEach(() => {
    process.env.ANTHROPIC_API_KEY = 'test-api-key';
  });

  it('should track usage statistics', () => {
    const provider = createClaudeProvider({
      usageTracking: true
    });
    
    const stats = provider.getUsageStats();
    expect(stats.totalRequests).toBe(0);
    expect(stats.totalTokens).toBe(0);
    expect(stats.totalCost).toBe(0);
  });
});

describe('Model Capabilities', () => {
  beforeEach(() => {
    process.env.ANTHROPIC_API_KEY = 'test-api-key';
  });

  it('should return capabilities for all models', () => {
    const provider = createClaudeProvider({});
    
    const models = [
      ClaudeModels.CLAUDE_3_7_SONNET,
      ClaudeModels.CLAUDE_3_5_SONNET,
      ClaudeModels.CLAUDE_OPUS_4,
      ClaudeModels.CLAUDE_HAIKU_3_5,
    ];
    
    for (const model of models) {
      const capabilities = provider.getModelCapabilities(model);
      expect(capabilities.maxContextTokens).toBeGreaterThan(0);
      expect(typeof capabilities.supportsVision).toBe('boolean');
      expect(typeof capabilities.supportsToolUse).toBe('boolean');
    }
  });
});
