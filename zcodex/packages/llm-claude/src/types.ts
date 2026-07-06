import { LLMProvider, LLMConfig, Message, Tool, ToolCall, StreamEvent } from '@zcodex/llm-core';

/**
 * Supported Claude models with capabilities
 */
export enum ClaudeModels {
  // Latest reasoning models
  CLAUDE_3_7_SONNET = 'claude-3-7-sonnet-20250219',
  CLAUDE_3_7_SONNET_LATEST = 'claude-3-7-sonnet-latest',
  
  // Best for coding tasks
  CLAUDE_3_5_SONNET = 'claude-3-5-sonnet-20241022',
  CLAUDE_3_5_SONNET_LATEST = 'claude-3-5-sonnet-latest',
  
  // Most powerful for complex operations
  CLAUDE_OPUS_4 = 'claude-opus-4-20250514',
  CLAUDE_OPUS = 'claude-3-opus-20240229',
  
  // Fast and efficient
  CLAUDE_HAIKU_3_5 = 'claude-3-5-haiku-20241022',
  CLAUDE_HAIKU = 'claude-3-haiku-20240307',
}

/**
 * Model routing strategy based on task complexity
 */
export enum ModelRoutingStrategy {
  AUTO = 'auto',           // Automatically select based on task
  BALANCED = 'balanced',   // Balance speed and capability
  PERFORMANCE = 'performance', // Maximum capability
  ECONOMY = 'economy',     // Cost-effective
}

/**
 * Extended thinking configuration
 */
export interface ExtendedThinkingConfig {
  enabled: boolean;
  budgetTokens?: number;    // Max tokens for reasoning
  includeInResponse?: boolean; // Include reasoning in output
}

/**
 * Context caching configuration
 */
export interface CacheConfig {
  enabled: boolean;
  ttlSeconds?: number;      // Cache time-to-live
  maxEntries?: number;      // Maximum cached conversations
}

/**
 * Claude-specific configuration
 */
export interface ClaudeConfig extends LLMConfig {
  apiKey: string;
  model?: ClaudeModels | string;
  routingStrategy?: ModelRoutingStrategy;
  extendedThinking?: ExtendedThinkingConfig;
  cache?: CacheConfig;
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  stopSequences?: string[];
  baseUrl?: string;         // Custom API endpoint
  timeout?: number;         // Request timeout in ms
  maxRetries?: number;      // Automatic retry count
  enableStreaming?: boolean;
  enableToolUse?: boolean;
  enableImageInput?: boolean;
  enableDocumentParsing?: boolean;
  usageTracking?: boolean;
  teamId?: string;          // For enterprise workspace
  auditLogging?: boolean;   // Log all API calls
}

/**
 * Claude message content types - matching Anthropic SDK exactly
 */
export type ClaudeContentBlock = 
  | { type: 'text'; text: string }
  | { type: 'image'; source: { type: 'base64' | 'url'; data: string; media_type: string } }
  | { type: 'document'; source: { type: 'base64' | 'url'; data: string; media_type: string; name?: string } }
  | { type: 'tool_use'; id: string; name: string; input: Record<string, any> }
  | { type: 'tool_result'; tool_use_id: string; content: string | Array<ClaudeContentBlock>; is_error?: boolean };

/**
 * Claude message format
 */
export interface ClaudeMessage {
  role: 'user' | 'assistant';
  content: string | Array<ClaudeContentBlock>;
}

/**
 * Tool definition for Claude
 */
export interface ClaudeTool {
  name: string;
  description: string;
  input_schema: {
    type: 'object';
    properties: Record<string, {
      type: string;
      description?: string;
      enum?: any[];
      items?: any;
    }>;
    required?: string[];
  };
}

/**
 * Tool execution result
 */
export interface ClaudeToolResult {
  tool_use_id: string;
  content: string | Array<ClaudeContentBlock>;
  is_error?: boolean;
}

/**
 * Usage statistics from Claude API
 */
export interface ClaudeUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadInputTokens?: number;
  cacheWriteInputTokens?: number;
  totalTokens: number;
  estimatedCost?: number;
}

/**
 * Streaming event types from Claude
 */
export type ClaudeStreamEvent =
  | { type: 'message_start'; message: { id: string; model: string; usage: ClaudeUsage } }
  | { type: 'content_block_start'; index: number; content_block: { type: string; text?: string; id?: string; name?: string; input?: any } }
  | { type: 'content_block_delta'; index: number; delta: { type: string; text?: string; partial_json?: string } }
  | { type: 'content_block_stop'; index: number }
  | { type: 'message_delta'; delta: { stop_reason: string | null; stop_sequence: string | null }; usage: { output_tokens: number } }
  | { type: 'message_stop' }
  | { type: 'error'; error: { type: string; message: string } };

/**
 * Model capability metadata
 */
export interface ModelCapability {
  maxContextTokens: number;
  maxOutputTokens: number;
  supportsVision: boolean;
  supportsToolUse: boolean;
  supportsExtendedThinking: boolean;
  supportsCaching: boolean;
  costPerInputToken: number;
  costPerOutputToken: number;
}

/**
 * Model routing decision
 */
export interface RoutingDecision {
  selectedModel: ClaudeModels;
  reason: string;
  confidence: number;
  alternatives: ClaudeModels[];
}
