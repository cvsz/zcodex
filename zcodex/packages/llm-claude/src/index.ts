/**
 * Claude Provider for zcodex
 * 
 * Full implementation of Anthropic Claude Platform features:
 * - Messages API with Claude 3.5/3.7 Sonnet, Opus, Haiku
 * - Extended thinking/reasoning tokens
 * - Native tool use and function calling
 * - Multi-turn conversation management
 * - Image input processing (OCR, diagram analysis)
 * - Document/PDF parsing support
 * - Context caching (up to 200K tokens)
 * - Real-time streaming responses
 * - Usage tracking and cost management
 * - Intelligent model routing
 */

export { ClaudeProvider } from './claude-provider';
export type { ClaudeModels } from './types';
export { MODEL_CATALOG as CLAUDE_MODELS, getModelByName as getModelCapability } from './models';
export { ClaudeConfig } from './types';
export { createClaudeProvider } from './factory';

export type {
  ClaudeMessage,
  ClaudeTool,
  ClaudeToolResult,
  ClaudeUsage,
  ClaudeStreamEvent,
} from './types';
