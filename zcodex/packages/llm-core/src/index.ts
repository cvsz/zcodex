/**
 * Core LLM interfaces for zcodex
 */

export interface LLMConfig {
  provider: string;
  apiKey?: string;
  baseUrl?: string;
  timeout?: number;
  maxRetries?: number;
}

export interface Message {
  role: 'user' | 'assistant' | 'system';
  content: string | Array<ContentBlock>;
}

export type ContentBlock = 
  | { type: 'text'; text: string }
  | { type: 'image'; data: string; mimeType?: string }
  | { type: 'tool_use'; id: string; name: string; input: Record<string, any> }
  | { type: 'tool_result'; tool_use_id: string; content: string };

export interface Tool {
  name: string;
  description: string;
  parameters: {
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

export interface ToolCall {
  id: string;
  name: string;
  arguments: Record<string, any>;
}

export interface LLMUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  cacheReadInputTokens?: number;
  cacheWriteInputTokens?: number;
}

export interface LLMResponse {
  content: string;
  model: string;
  finishReason: 'stop' | 'length' | 'tool_calls' | 'content_filter';
  usage: LLMUsage;
  toolCalls?: ToolCall[];
  taskId?: string;
  metadata?: Record<string, any>;
}

export type StreamEvent =
  | { type: 'start'; messageId: string; model: string }
  | { type: 'content'; delta: string }
  | { type: 'tool_call'; toolCall: ToolCall }
  | { type: 'usage'; usage: LLMUsage }
  | { type: 'end'; finishReason: string }
  | { type: 'error'; error: Error }
  | { type: 'token'; data: { token: string } }
  | { type: 'finish'; data: { reason: string } }
  | { type: 'complete'; data: { content: string; toolCalls?: ToolCall[]; usage: LLMUsage; model: string } };

export abstract class LLMProvider {
  abstract generate(messages: Message[], options?: GenerateOptions): Promise<LLMResponse>;
  abstract generateStream(messages: Message[], options?: GenerateOptions): AsyncGenerator<StreamEvent>;
}

export interface GenerateOptions {
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  tools?: Tool[];
  toolChoice?: 'auto' | 'required' | { name: string };
  stopSequences?: string[];
}
