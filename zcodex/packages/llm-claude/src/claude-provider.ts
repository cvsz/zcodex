import Anthropic from '@anthropic-ai/sdk';
import { LLMProvider, Message, Tool, ToolCall, StreamEvent, LLMResponse, LLMUsage, GenerateOptions, ContentBlock } from '@zcodex/llm-core';
import {
  ClaudeConfig,
  ClaudeModels,
  ModelRoutingStrategy,
  ClaudeMessage,
  ClaudeTool,
  ClaudeContentBlock,
  ClaudeStreamEvent,
  ModelCapability,
  RoutingDecision,
} from './types';

/**
 * Model capability definitions with pricing (as of 2025)
 */
const MODEL_CAPABILITIES: Record<string, ModelCapability> = {
  [ClaudeModels.CLAUDE_3_7_SONNET]: {
    maxContextTokens: 200000,
    maxOutputTokens: 64000,
    supportsVision: true,
    supportsToolUse: true,
    supportsExtendedThinking: true,
    supportsCaching: true,
    costPerInputToken: 3e-6,
    costPerOutputToken: 15e-6,
  },
  [ClaudeModels.CLAUDE_3_5_SONNET]: {
    maxContextTokens: 200000,
    maxOutputTokens: 8192,
    supportsVision: true,
    supportsToolUse: true,
    supportsExtendedThinking: false,
    supportsCaching: true,
    costPerInputToken: 3e-6,
    costPerOutputToken: 15e-6,
  },
  [ClaudeModels.CLAUDE_OPUS_4]: {
    maxContextTokens: 200000,
    maxOutputTokens: 64000,
    supportsVision: true,
    supportsToolUse: true,
    supportsExtendedThinking: true,
    supportsCaching: true,
    costPerInputToken: 15e-6,
    costPerOutputToken: 75e-6,
  },
  [ClaudeModels.CLAUDE_HAIKU_3_5]: {
    maxContextTokens: 200000,
    maxOutputTokens: 8192,
    supportsVision: true,
    supportsToolUse: true,
    supportsExtendedThinking: false,
    supportsCaching: true,
    costPerInputToken: 0.8e-6,
    costPerOutputToken: 4e-6,
  },
};

/**
 * Task complexity levels for model routing
 */
enum TaskComplexity {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  VERY_HIGH = 'very_high',
}

/**
 * Claude AI Provider implementation with full platform support
 */
export class ClaudeProvider extends LLMProvider {
  private client: Anthropic;
  private config: ClaudeConfig;
  private cache: Map<string, { response: LLMResponse; timestamp: number }> = new Map();
  private usageStats: { totalRequests: number; totalTokens: number; totalCost: number } = {
    totalRequests: 0,
    totalTokens: 0,
    totalCost: 0,
  };

  constructor(config: ClaudeConfig) {
    super();
    this.config = config;
    
    this.client = new Anthropic({
      apiKey: config.apiKey,
      baseURL: config.baseUrl,
      timeout: config.timeout || 60000,
      maxRetries: config.maxRetries || 3,
    });
  }

  /**
   * Alias for complete() to match LLMProvider interface
   */
  async generate(messages: Message[], options?: GenerateOptions): Promise<LLMResponse> {
    return this.complete(messages, options);
  }

  /**
   * Alias for streamComplete() to match LLMProvider interface
   */
  async *generateStream(messages: Message[], options?: GenerateOptions): AsyncGenerator<StreamEvent> {
    yield* this.streamComplete(messages, options);
  }

  /**
   * Get the current model based on routing strategy
   */
  private getModel(): string {
    if (this.config.model) {
      return this.config.model;
    }

    const strategy = this.config.routingStrategy || ModelRoutingStrategy.AUTO;
    
    switch (strategy) {
      case ModelRoutingStrategy.PERFORMANCE:
        return ClaudeModels.CLAUDE_OPUS_4;
      case ModelRoutingStrategy.ECONOMY:
        return ClaudeModels.CLAUDE_HAIKU_3_5;
      case ModelRoutingStrategy.BALANCED:
        return ClaudeModels.CLAUDE_3_5_SONNET;
      case ModelRoutingStrategy.AUTO:
      default:
        return ClaudeModels.CLAUDE_3_5_SONNET; // Default to balanced
    }
  }

  /**
   * Analyze task complexity for model routing
   */
  private analyzeTaskComplexity(messages: Message[]): TaskComplexity {
    const lastMessage = messages[messages.length - 1]?.content || '';
    const combinedContent = messages.map(m => m.content).join(' ');
    
    // Indicators of high complexity
    const highComplexityIndicators = [
      /implement.*from scratch/i,
      /refactor.*entire/i,
      /optimize.*performance/i,
      /security.*vulnerability/i,
      /architecture.*design/i,
      /multi-step.*plan/i,
      /\bdebug\b.*\bcomplex\b/i,
      /integrate.*multiple/i,
    ];

    // Indicators of low complexity
    const lowComplexityIndicators = [
      /what is/i,
      /explain.*simple/i,
      /fix.*typo/i,
      /add.*comment/i,
      /rename/i,
      /\?$/,
    ];

    let complexityScore = 0;

    for (const indicator of highComplexityIndicators) {
      if (indicator.test(combinedContent)) {
        complexityScore += 2;
      }
    }

    for (const indicator of lowComplexityIndicators) {
      if (indicator.test(combinedContent)) {
        complexityScore -= 1;
      }
    }

    // Adjust based on message length
    if (combinedContent.length > 2000) {
      complexityScore += 1;
    }

    if (complexityScore >= 4) return TaskComplexity.VERY_HIGH;
    if (complexityScore >= 2) return TaskComplexity.HIGH;
    if (complexityScore >= 0) return TaskComplexity.MEDIUM;
    return TaskComplexity.LOW;
  }

  /**
   * Route to appropriate model based on task complexity
   */
  private routeModel(taskComplexity: TaskComplexity): string {
    if (this.config.routingStrategy !== ModelRoutingStrategy.AUTO) {
      return this.getModel();
    }

    switch (taskComplexity) {
      case TaskComplexity.VERY_HIGH:
        return ClaudeModels.CLAUDE_OPUS_4;
      case TaskComplexity.HIGH:
        return ClaudeModels.CLAUDE_3_7_SONNET;
      case TaskComplexity.MEDIUM:
        return ClaudeModels.CLAUDE_3_5_SONNET;
      case TaskComplexity.LOW:
        return ClaudeModels.CLAUDE_HAIKU_3_5;
      default:
        return ClaudeModels.CLAUDE_3_5_SONNET;
    }
  }

  /**
   * Convert internal messages to Claude format
   */
  private convertMessages(messages: Message[], tools?: Tool[]): ClaudeMessage[] {
    return messages.map(msg => {
      if (typeof msg.content === 'string') {
        return {
          role: msg.role as 'user' | 'assistant',
          content: msg.content,
        };
      }
      
      // Convert content blocks
      const contentBlocks: ClaudeContentBlock[] = msg.content.map(block => {
        if (block.type === 'text') {
          return { type: 'text', text: block.text };
        } else if (block.type === 'image') {
          // Convert internal image format to Claude's source format
          return {
            type: 'image',
            source: {
              type: block.mimeType?.includes('url') || block.data.startsWith('http') ? 'url' : 'base64',
              data: block.data,
              media_type: block.mimeType || 'image/jpeg',
            },
          };
        } else if (block.type === 'tool_use') {
          return {
            type: 'tool_use',
            id: block.id,
            name: block.name,
            input: block.input,
          };
        } else if (block.type === 'tool_result') {
          return {
            type: 'tool_result',
            tool_use_id: block.tool_use_id,
            content: block.content,
          };
        }
        throw new Error(`Unknown content block type: ${(block as any).type}`);
      });
      
      return {
        role: msg.role as 'user' | 'assistant',
        content: contentBlocks,
      };
    });
  }

  /**
   * Convert internal tools to Claude format
   */
  private convertTools(tools: Tool[]): ClaudeTool[] {
    return tools.map(tool => ({
      name: tool.name,
      description: tool.description,
      input_schema: {
        type: 'object',
        properties: Object.fromEntries(
          Object.entries(tool.parameters.properties).map(([key, value]) => [
            key,
            {
              type: value.type,
              description: value.description,
              enum: value.enum,
              items: value.items,
            },
          ])
        ),
        required: tool.parameters.required || [],
      },
    }));
  }

  /**
   * Check cache for existing response
   */
  private async getCachedResponse(cacheKey: string): Promise<LLMResponse | null> {
    if (!this.config.cache?.enabled) {
      return null;
    }

    const cached = this.cache.get(cacheKey);
    if (!cached) {
      return null;
    }

    const ttl = this.config.cache.ttlSeconds || 3600;
    const isExpired = Date.now() - cached.timestamp > ttl * 1000;

    if (isExpired) {
      this.cache.delete(cacheKey);
      return null;
    }

    return cached.response;
  }

  /**
   * Cache a response
   */
  private setCachedResponse(cacheKey: string, response: LLMResponse): void {
    if (!this.config.cache?.enabled) {
      return;
    }

    const maxEntries = this.config.cache.maxEntries || 100;
    
    if (this.cache.size >= maxEntries) {
      // Remove oldest entry
      const firstKey = this.cache.keys().next().value;
      if (firstKey) {
        this.cache.delete(firstKey);
      }
    }

    this.cache.set(cacheKey, {
      response,
      timestamp: Date.now(),
    });
  }

  /**
   * Generate cache key from messages
   */
  private generateCacheKey(messages: Message[]): string {
    const content = messages.map(m => `${m.role}:${m.content}`).join('|');
    return require('crypto').createHash('sha256').update(content).digest('hex');
  }

  /**
   * Calculate usage and cost
   */
  private calculateUsage(
    inputTokens: number,
    outputTokens: number,
    model: string,
    cacheReadTokens?: number,
    cacheWriteTokens?: number
  ): LLMUsage & { estimatedCost: number } {
    const capabilities = MODEL_CAPABILITIES[model] || MODEL_CAPABILITIES[ClaudeModels.CLAUDE_3_5_SONNET];
    
    const baseCost = (inputTokens * capabilities.costPerInputToken) + 
                     (outputTokens * capabilities.costPerOutputToken);
    
    const cacheCost = ((cacheReadTokens || 0) * capabilities.costPerInputToken * 0.1) + // 10% for cache read
                      ((cacheWriteTokens || 0) * capabilities.costPerInputToken * 1.25); // 125% for cache write

    const estimatedCost = baseCost + cacheCost;

    // Update stats
    this.usageStats.totalRequests++;
    this.usageStats.totalTokens += inputTokens + outputTokens;
    this.usageStats.totalCost += estimatedCost;

    return {
      inputTokens,
      outputTokens,
      totalTokens: inputTokens + outputTokens,
      cacheReadInputTokens: cacheReadTokens,
      cacheWriteInputTokens: cacheWriteTokens,
      estimatedCost,
    };
  }

  /**
   * Log API call for audit
   */
  private auditLog(
    action: string,
    model: string,
    tokens: number,
    cost: number,
    metadata?: Record<string, any>
  ): void {
    if (!this.config.auditLogging) {
      return;
    }

    const logEntry = {
      timestamp: new Date().toISOString(),
      action,
      model,
      tokens,
      cost,
      teamId: this.config.teamId,
      ...metadata,
    };

    // In production, send to logging service
    console.log('[AUDIT]', JSON.stringify(logEntry));
  }

  /**
   * Main completion method
   */
  async complete(
    messages: Message[],
    options?: {
      tools?: Tool[];
      temperature?: number;
      maxTokens?: number;
      stream?: boolean;
    }
  ): Promise<LLMResponse> {
    const cacheKey = this.generateCacheKey(messages);
    
    // Check cache first
    const cached = await this.getCachedResponse(cacheKey);
    if (cached) {
      return cached;
    }

    // Analyze task and route model
    const taskComplexity = this.analyzeTaskComplexity(messages);
    const model = this.routeModel(taskComplexity);

    const claudeMessages = this.convertMessages(messages, options?.tools);
    const claudeTools = options?.tools ? this.convertTools(options.tools) : undefined;

    try {
      const params: Anthropic.MessageCreateParams = {
        model,
        messages: claudeMessages as any,
        max_tokens: options?.maxTokens || this.config.maxTokens || 4096,
        temperature: options?.temperature ?? this.config.temperature ?? 0.7,
        top_p: this.config.topP,
        top_k: this.config.topK,
        stop_sequences: this.config.stopSequences,
        stream: false,
      };

      if (claudeTools && this.config.enableToolUse !== false) {
        params.tools = claudeTools as any;
      }

      // Extended thinking configuration
      if (this.config.extendedThinking?.enabled) {
        (params as any).thinking = {
          type: 'enabled',
          budget_tokens: this.config.extendedThinking.budgetTokens || 10000,
        };
      }

      const response = await this.client.messages.create(params);

      // Extract content and tool calls
      const contentBlocks = response.content;
      let textContent = '';
      const toolCalls: ToolCall[] = [];

      for (const block of contentBlocks) {
        if (block.type === 'text') {
          textContent += block.text;
        } else if (block.type === 'tool_use') {
          toolCalls.push({
            id: block.id,
            name: block.name,
            arguments: block.input as Record<string, any>,
          });
        }
      }

      // Calculate usage
      const usage = this.calculateUsage(
        response.usage.input_tokens,
        response.usage.output_tokens,
        model,
        (response.usage as any).cache_read_input_tokens,
        (response.usage as any).cache_write_input_tokens
      );

      const llmResponse: LLMResponse = {
        content: textContent,
        toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
        usage,
        model: response.model,
        finishReason: response.stop_reason as 'stop' | 'length' | 'tool_calls' | 'content_filter',
        metadata: {
          taskId: response.id,
          taskComplexity,
          routingStrategy: this.config.routingStrategy,
        },
      };

      // Cache response
      this.setCachedResponse(cacheKey, llmResponse);

      // Audit log
      this.auditLog('complete', model, usage.totalTokens, usage.estimatedCost || 0, {
        taskComplexity,
        toolCalls: toolCalls.length,
      });

      return llmResponse;
    } catch (error: any) {
      this.auditLog('error', model, 0, 0, {
        errorType: error.type,
        errorMessage: error.message,
      });
      throw error;
    }
  }

  /**
   * Streaming completion
   */
  async *streamComplete(
    messages: Message[],
    options?: {
      tools?: Tool[];
      temperature?: number;
      maxTokens?: number;
    }
  ): AsyncGenerator<StreamEvent> {
    if (!this.config.enableStreaming) {
      throw new Error('Streaming is not enabled in configuration');
    }

    const model = this.getModel();
    const claudeMessages = this.convertMessages(messages, options?.tools);
    const claudeTools = options?.tools ? this.convertTools(options.tools) : undefined;

    try {
      const params: Anthropic.MessageStreamParams = {
        model,
        messages: claudeMessages,
        max_tokens: options?.maxTokens || this.config.maxTokens || 4096,
        temperature: options?.temperature ?? this.config.temperature ?? 0.7,
        stream: true,
      };

      if (claudeTools && this.config.enableToolUse !== false) {
        params.tools = claudeTools;
      }

      const stream = this.client.messages.stream(params);

      let accumulatedText = '';
      const toolCalls: ToolCall[] = [];
      let messageId = '';
      let inputTokens = 0;
      let outputTokens = 0;

      for await (const event of stream) {
        const claudeEvent = event as ClaudeStreamEvent;
        
        switch (claudeEvent.type) {
          case 'message_start':
            messageId = claudeEvent.message.id;
            inputTokens = claudeEvent.message.usage.inputTokens;
            yield {
              type: 'start',
              data: { messageId, model },
            };
            break;

          case 'content_block_start':
            if (claudeEvent.content_block.type === 'tool_use') {
              toolCalls.push({
                id: claudeEvent.content_block.id!,
                name: claudeEvent.content_block.name!,
                arguments: '',
              });
            }
            break;

          case 'content_block_delta':
            if (claudeEvent.delta.type === 'text_delta') {
              accumulatedText += claudeEvent.delta.text || '';
              yield {
                type: 'token',
                data: { token: claudeEvent.delta.text || '' },
              };
            } else if (claudeEvent.delta.type === 'input_json_delta' && toolCalls.length > 0) {
              // Accumulate tool call arguments
              const lastToolCall = toolCalls[toolCalls.length - 1];
              if (lastToolCall) {
                lastToolCall.arguments += claudeEvent.delta.partial_json || '';
              }
            }
            break;

          case 'message_delta':
            outputTokens = claudeEvent.usage.output_tokens;
            yield {
              type: 'finish',
              data: {
                reason: claudeEvent.delta.stop_reason || 'stop',
              },
            };
            break;

          case 'message_stop':
            // Calculate final usage
            const usage = this.calculateUsage(inputTokens, outputTokens, model);
            
            yield {
              type: 'complete',
              data: {
                content: accumulatedText,
                toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
                usage,
                model,
              },
            };
            break;

          case 'error':
            yield {
              type: 'error',
              data: { error: claudeEvent.error.message },
            };
            break;
        }
      }
    } catch (error: any) {
      yield {
        type: 'error',
        data: { error: error.message },
      };
      throw error;
    }
  }

  /**
   * Process image input
   */
  async processImage(
    imageData: string,
    mediaType: string,
    prompt?: string
  ): Promise<{ description: string; text?: string }> {
    const messages: Message[] = [
      {
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', data: imageData, mediaType } },
          ...(prompt ? [{ type: 'text', text: prompt }] : []),
        ].filter(Boolean) as any,
      },
    ];

    const response = await this.complete(messages);
    
    return {
      description: response.content,
      text: undefined, // OCR text would be in content
    };
  }

  /**
   * Parse document (PDF, etc.)
   */
  async parseDocument(
    documentData: string,
    mediaType: string,
    fileName?: string
  ): Promise<{ summary: string; extractedText?: string }> {
    const messages: Message[] = [
      {
        role: 'user',
        content: [
          { 
            type: 'document', 
            source: { 
              type: 'base64', 
              data: documentData, 
              mediaType,
              name: fileName,
            } 
          },
          { type: 'text', text: 'Please summarize this document and extract key information.' },
        ],
      },
    ];

    const response = await this.complete(messages);
    
    return {
      summary: response.content,
      extractedText: undefined,
    };
  }

  /**
   * Get model capabilities
   */
  getModelCapabilities(model?: string): ModelCapability {
    const modelKey = model || this.getModel();
    return MODEL_CAPABILITIES[modelKey] || MODEL_CAPABILITIES[ClaudeModels.CLAUDE_3_5_SONNET];
  }

  /**
   * Get usage statistics
   */
  getUsageStats(): typeof this.usageStats {
    return { ...this.usageStats };
  }

  /**
   * Clear cache
   */
  clearCache(): void {
    this.cache.clear();
  }

  /**
   * Get routing decision for a task
   */
  getRoutingDecision(messages: Message[]): RoutingDecision {
    const taskComplexity = this.analyzeTaskComplexity(messages);
    const selectedModel = this.routeModel(taskComplexity);
    
    const alternatives: ClaudeModels[] = [];
    if (selectedModel !== ClaudeModels.CLAUDE_HAIKU_3_5) {
      alternatives.push(ClaudeModels.CLAUDE_HAIKU_3_5);
    }
    if (selectedModel !== ClaudeModels.CLAUDE_3_5_SONNET) {
      alternatives.push(ClaudeModels.CLAUDE_3_5_SONNET);
    }
    if (selectedModel !== ClaudeModels.CLAUDE_OPUS_4) {
      alternatives.push(ClaudeModels.CLAUDE_OPUS_4);
    }

    return {
      selectedModel: selectedModel as ClaudeModels,
      reason: `Task complexity: ${taskComplexity}`,
      confidence: 0.9,
      alternatives,
    };
  }
}
