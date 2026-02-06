import { TokensResult, BundledLanguage, BundledTheme } from 'shiki';

/**
 * Result from code highlighting
 */
type HighlightResult = TokensResult;
/**
 * Options for highlighting code
 */
interface HighlightOptions {
    code: string;
    language: BundledLanguage;
    themes: [string, string];
}
/**
 * Plugin for code syntax highlighting (Shiki)
 */
interface CodeHighlighterPlugin {
    name: "shiki";
    type: "code-highlighter";
    /**
     * Highlight code and return tokens
     * Returns null if highlighting not ready yet (async loading)
     * Use callback for async result
     */
    highlight: (options: HighlightOptions, callback?: (result: HighlightResult) => void) => HighlightResult | null;
    /**
     * Check if language is supported
     */
    supportsLanguage: (language: BundledLanguage) => boolean;
    /**
     * Get list of supported languages
     */
    getSupportedLanguages: () => BundledLanguage[];
    /**
     * Get the configured themes
     */
    getThemes: () => [BundledTheme, BundledTheme];
}
/**
 * Options for creating a code plugin
 */
interface CodePluginOptions {
    /**
     * Default themes for syntax highlighting [light, dark]
     * @default ["github-light", "github-dark"]
     */
    themes?: [BundledTheme, BundledTheme];
}
/**
 * Create a code plugin with optional configuration
 */
declare function createCodePlugin(options?: CodePluginOptions): CodeHighlighterPlugin;
/**
 * Pre-configured code plugin with default settings
 */
declare const code: CodeHighlighterPlugin;

export { type CodeHighlighterPlugin, type CodePluginOptions, type HighlightOptions, type HighlightResult, code, createCodePlugin };
