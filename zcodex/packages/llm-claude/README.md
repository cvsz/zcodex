# @zcodex/llm-claude

Claude AI provider for zcodex with full Anthropic platform support.

## Features

- **Multi-Model Support**: Claude 3.7 Sonnet, 3.5 Sonnet, Opus 4, Haiku 3.5
- **Intelligent Model Routing**: Automatic model selection based on task complexity
- **Extended Thinking**: Advanced reasoning with configurable token budgets
- **Context Caching**: Up to 200K tokens with automatic cache management
- **Tool Use**: Native function calling and tool execution
- **Vision**: Image input processing (OCR, diagram analysis)
- **Document Parsing**: PDF and document understanding
- **Streaming**: Real-time response streaming
- **Usage Tracking**: Cost monitoring and optimization
- **Enterprise Ready**: Audit logging, team workspaces, RBAC

## Installation

```bash
npm install @zcodex/llm-claude
```

## Quick Start

```typescript
import { createClaudeProvider } from '@zcodex/llm-claude';

// Create provider with API key
const provider = createClaudeProvider({
  apiKey: 'your-api-key', // or set ANTHROPIC_API_KEY env var
});

// Simple completion
const response = await provider.complete([
  { role: 'user', content: 'Hello, Claude!' }
]);

console.log(response.content);
```

## Factory Functions

### Standard Provider
```typescript
const provider = createClaudeProvider({
  model: 'claude-3-5-sonnet-20241022',
  temperature: 0.7,
  maxTokens: 4096,
});
```

### Coding Optimized
```typescript
const codingProvider = createCodingProvider({
  temperature: 0.3, // Lower for deterministic code
});
```

### Reasoning Optimized
```typescript
const reasoningProvider = createReasoningProvider({
  extendedThinking: {
    enabled: true,
    budgetTokens: 16000,
  },
});
```

### Cost-Effective
```typescript
const economyProvider = createEconomyProvider({
  // Uses Haiku 3.5 by default
});
```

### Enterprise
```typescript
const enterpriseProvider = createEnterpriseProvider({
  teamId: 'your-team-id',
  auditLogging: true,
});
```

## Model Routing

Automatic model selection based on task complexity:

```typescript
import { ModelRoutingStrategy } from '@zcodex/llm-claude';

const provider = createClaudeProvider({
  routingStrategy: ModelRoutingStrategy.AUTO, // auto | balanced | performance | economy
});

// Get routing decision
const decision = provider.getRoutingDecision([
  { role: 'user', content: 'Implement a complex refactoring...' }
]);

console.log(decision.selectedModel); // e.g., 'claude-opus-4-20250514'
console.log(decision.reason); // "Task complexity: very_high"
```

## Streaming

```typescript
for await (const event of provider.streamComplete([
  { role: 'user', content: 'Write a long story...' }
])) {
  if (event.type === 'token') {
    process.stdout.write(event.data.token);
  }
}
```

## Tool Use

```typescript
const tools = [{
  name: 'execute_command',
  description: 'Execute a shell command',
  parameters: {
    type: 'object',
    properties: {
      command: { type: 'string', description: 'The command to execute' },
    },
    required: ['command'],
  },
}];

const response = await provider.complete([
  { role: 'user', content: 'List files in current directory' }
], { tools });

if (response.toolCalls) {
  for (const toolCall of response.toolCalls) {
    console.log(`Calling ${toolCall.name}...`);
  }
}
```

## Vision

```typescript
const result = await provider.processImage(
  base64ImageData,
  'image/png',
  'What is in this image?'
);

console.log(result.description);
```

## Document Parsing

```typescript
const result = await provider.parseDocument(
  base64PdfData,
  'application/pdf',
  'document.pdf'
);

console.log(result.summary);
```

## Usage Tracking

```typescript
const stats = provider.getUsageStats();
console.log(`Total requests: ${stats.totalRequests}`);
console.log(`Total tokens: ${stats.totalTokens}`);
console.log(`Total cost: $${stats.totalCost.toFixed(4)}`);
```

## Configuration Options

```typescript
interface ClaudeConfig {
  apiKey: string;
  model?: string;
  routingStrategy?: ModelRoutingStrategy;
  extendedThinking?: { enabled: boolean; budgetTokens?: number };
  cache?: { enabled: boolean; ttlSeconds?: number; maxEntries?: number };
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  stopSequences?: string[];
  baseUrl?: string;
  timeout?: number;
  maxRetries?: number;
  enableStreaming?: boolean;
  enableToolUse?: boolean;
  enableImageInput?: boolean;
  enableDocumentParsing?: boolean;
  usageTracking?: boolean;
  teamId?: string;
  auditLogging?: boolean;
}
```

## Models

| Model | Context | Output | Vision | Tools | Thinking | Cost/1K Input |
|-------|---------|--------|--------|-------|----------|---------------|
| Claude 3.7 Sonnet | 200K | 64K | ✓ | ✓ | ✓ | $0.003 |
| Claude 3.5 Sonnet | 200K | 8K | ✓ | ✓ | ✗ | $0.003 |
| Claude Opus 4 | 200K | 64K | ✓ | ✓ | ✓ | $0.015 |
| Claude Haiku 3.5 | 200K | 8K | ✓ | ✓ | ✗ | $0.0008 |

## License

MIT
