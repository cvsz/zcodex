/**
 * Model definitions and routing utilities
 */

import { ClaudeModels, ModelCapability, ModelRoutingStrategy } from './types';

/**
 * Complete model catalog with capabilities
 */
export const MODEL_CATALOG: Record<ClaudeModels, ModelCapability> = {
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
  [ClaudeModels.CLAUDE_3_7_SONNET_LATEST]: {
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
  [ClaudeModels.CLAUDE_3_5_SONNET_LATEST]: {
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
  [ClaudeModels.CLAUDE_OPUS]: {
    maxContextTokens: 200000,
    maxOutputTokens: 4096,
    supportsVision: true,
    supportsToolUse: true,
    supportsExtendedThinking: false,
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
  [ClaudeModels.CLAUDE_HAIKU]: {
    maxContextTokens: 200000,
    maxOutputTokens: 4096,
    supportsVision: true,
    supportsToolUse: true,
    supportsExtendedThinking: false,
    supportsCaching: true,
    costPerInputToken: 0.25e-6,
    costPerOutputToken: 1.25e-6,
  },
};

/**
 * Get model by name (case-insensitive)
 */
export function getModelByName(name: string): ClaudeModels | null {
  const normalizedName = name.toLowerCase().replace(/[_-]/g, '-');
  
  for (const [key, value] of Object.entries(ClaudeModels)) {
    if (value.toLowerCase().replace(/[_-]/g, '-') === normalizedName) {
      return value as ClaudeModels;
    }
  }
  
  return null;
}

/**
 * Check if a model supports a specific feature
 */
export function modelSupportsFeature(
  model: ClaudeModels | string,
  feature: keyof Omit<ModelCapability, 'costPerInputToken' | 'costPerOutputToken'>
): boolean {
  const capability = MODEL_CATALOG[model as ClaudeModels];
  if (!capability) {
    // Default to assuming support for unknown models
    return true;
  }
  return capability[feature] || false;
}

/**
 * Get the most cost-effective model for a given context size
 */
export function getMostEconomicalModel(contextTokens: number): ClaudeModels {
  const eligibleModels = Object.values(ClaudeModels).filter(
    (model) => MODEL_CATALOG[model].maxContextTokens >= contextTokens
  );

  if (eligibleModels.length === 0) {
    throw new Error(`No model supports ${contextTokens} context tokens`);
  }

  // Sort by input token cost
  return eligibleModels.reduce((cheapest, current) => {
    const cheapestCost = MODEL_CATALOG[cheapest].costPerInputToken;
    const currentCost = MODEL_CATALOG[current].costPerInputToken;
    return currentCost < cheapestCost ? current : cheapest;
  });
}

/**
 * Get recommended model for a use case
 */
export function getRecommendedModel(useCase: string): ClaudeModels {
  const useCaseLower = useCase.toLowerCase();

  if (useCaseLower.includes('code') || useCaseLower.includes('programming')) {
    return ClaudeModels.CLAUDE_3_5_SONNET;
  }

  if (useCaseLower.includes('reason') || useCaseLower.includes('analyze') || useCaseLower.includes('complex')) {
    return ClaudeModels.CLAUDE_3_7_SONNET;
  }

  if (useCaseLower.includes('vision') || useCaseLower.includes('image') || useCaseLower.includes('diagram')) {
    return ClaudeModels.CLAUDE_3_5_SONNET;
  }

  if (useCaseLower.includes('fast') || useCaseLower.includes('quick') || useCaseLower.includes('simple')) {
    return ClaudeModels.CLAUDE_HAIKU_3_5;
  }

  if (useCaseLower.includes('powerful') || useCaseLower.includes('advanced')) {
    return ClaudeModels.CLAUDE_OPUS_4;
  }

  // Default balanced choice
  return ClaudeModels.CLAUDE_3_5_SONNET;
}

/**
 * Compare two models
 */
export function compareModels(
  model1: ClaudeModels,
  model2: ClaudeModels
): {
  faster: ClaudeModels;
  moreCapable: ClaudeModels;
  moreCostEffective: ClaudeModels;
  details: Record<string, any>;
} {
  const cap1 = MODEL_CATALOG[model1];
  const cap2 = MODEL_CATALOG[model2];

  const avgCost1 = (cap1.costPerInputToken + cap1.costPerOutputToken) / 2;
  const avgCost2 = (cap2.costPerInputToken + cap2.costPerOutputToken) / 2;

  return {
    faster: cap1.maxOutputTokens > cap2.maxOutputTokens ? model1 : model2,
    moreCapable: cap1.maxContextTokens > cap2.maxContextTokens ? model1 : model2,
    moreCostEffective: avgCost1 < avgCost2 ? model1 : model2,
    details: {
      [model1]: cap1,
      [model2]: cap2,
      costDifference: Math.abs(avgCost1 - avgCost2),
    },
  };
}

/**
 * All available model IDs
 */
export const ALL_MODEL_IDS: string[] = Object.values(ClaudeModels);

/**
 * Models that support vision
 */
export const VISION_MODELS: ClaudeModels[] = Object.values(ClaudeModels).filter(
  (model) => MODEL_CATALOG[model].supportsVision
);

/**
 * Models that support tool use
 */
export const TOOL_MODELS: ClaudeModels[] = Object.values(ClaudeModels).filter(
  (model) => MODEL_CATALOG[model].supportsToolUse
);

/**
 * Models that support extended thinking
 */
export const THINKING_MODELS: ClaudeModels[] = Object.values(ClaudeModels).filter(
  (model) => MODEL_CATALOG[model].supportsExtendedThinking
);

/**
 * Models ordered by cost (cheapest first)
 */
export const MODELS_BY_COST: ClaudeModels[] = Object.values(ClaudeModels).sort(
  (a, b) =>
    MODEL_CATALOG[a].costPerInputToken - MODEL_CATALOG[b].costPerInputToken
);

/**
 * Models ordered by capability (most capable first)
 */
export const MODELS_BY_CAPABILITY: ClaudeModels[] = Object.values(ClaudeModels).sort(
  (a, b) =>
    MODEL_CATALOG[b].maxContextTokens - MODEL_CATALOG[a].maxContextTokens
);
