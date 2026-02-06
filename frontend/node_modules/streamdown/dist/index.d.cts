import * as react_jsx_runtime from 'react/jsx-runtime';
import * as react from 'react';
import { JSX, ComponentType } from 'react';
import { MermaidConfig } from 'mermaid';
import { RemendOptions } from 'remend';
import { BundledLanguage, BundledTheme } from 'shiki';
export { BundledLanguage, BundledTheme } from 'shiki';
import { PluggableList, Pluggable } from 'unified';
import { Element } from 'hast';
import { Options as Options$1 } from 'remark-rehype';

interface ExtraProps {
    node?: Element | undefined;
}
type Components = {
    [Key in keyof JSX.IntrinsicElements]?: ComponentType<JSX.IntrinsicElements[Key] & ExtraProps> | keyof JSX.IntrinsicElements;
};
interface Options {
    children?: string;
    components?: Components;
    rehypePlugins?: PluggableList;
    remarkPlugins?: PluggableList;
    remarkRehypeOptions?: Readonly<Options$1>;
}

/**
 * A single token in a highlighted line
 */
interface HighlightToken {
    content: string;
    color?: string;
    bgColor?: string;
    htmlStyle?: Record<string, string>;
    htmlAttrs?: Record<string, string>;
    offset?: number;
}
/**
 * Result from code highlighting (compatible with shiki's TokensResult)
 */
interface HighlightResult {
    tokens: HighlightToken[][];
    fg?: string;
    bg?: string;
}
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
 * Mermaid instance interface
 */
interface MermaidInstance {
    initialize: (config: MermaidConfig) => void;
    render: (id: string, source: string) => Promise<{
        svg: string;
    }>;
}
/**
 * Plugin for diagram rendering (Mermaid)
 */
interface DiagramPlugin {
    name: "mermaid";
    type: "diagram";
    /**
     * Language identifier for code blocks
     */
    language: string;
    /**
     * Get the mermaid instance (initialized with optional config)
     */
    getMermaid: (config?: MermaidConfig) => MermaidInstance;
}
/**
 * Plugin for math rendering (KaTeX)
 */
interface MathPlugin {
    name: "katex";
    type: "math";
    /**
     * Get remark plugin for parsing math syntax
     */
    remarkPlugin: Pluggable;
    /**
     * Get rehype plugin for rendering math
     */
    rehypePlugin: Pluggable;
    /**
     * Get CSS styles for math rendering (injected into head)
     */
    getStyles?: () => string;
}
/**
 * Plugin for CJK text handling
 */
interface CjkPlugin {
    name: "cjk";
    type: "cjk";
    /**
     * Remark plugins that must run BEFORE remarkGfm
     * (e.g., remark-cjk-friendly which modifies emphasis handling)
     */
    remarkPluginsBefore: Pluggable[];
    /**
     * Remark plugins that must run AFTER remarkGfm
     * (e.g., autolink boundary splitting, strikethrough enhancements)
     */
    remarkPluginsAfter: Pluggable[];
    /**
     * @deprecated Use remarkPluginsBefore and remarkPluginsAfter instead
     * All remark plugins (for backwards compatibility)
     */
    remarkPlugins: Pluggable[];
}
/**
 * Plugin configuration passed to Streamdown
 */
interface PluginConfig {
    code?: CodeHighlighterPlugin;
    mermaid?: DiagramPlugin;
    math?: MathPlugin;
    cjk?: CjkPlugin;
}

declare const parseMarkdownIntoBlocks: (markdown: string) => string[];

type ControlsConfig = boolean | {
    table?: boolean;
    code?: boolean;
    mermaid?: boolean | {
        download?: boolean;
        copy?: boolean;
        fullscreen?: boolean;
        panZoom?: boolean;
    };
};
interface LinkSafetyModalProps {
    url: string;
    isOpen: boolean;
    onClose: () => void;
    onConfirm: () => void;
}
interface LinkSafetyConfig {
    enabled: boolean;
    onLinkCheck?: (url: string) => Promise<boolean> | boolean;
    renderModal?: (props: LinkSafetyModalProps) => React.ReactNode;
}
interface MermaidErrorComponentProps {
    error: string;
    chart: string;
    retry: () => void;
}
interface MermaidOptions {
    config?: MermaidConfig;
    errorComponent?: React.ComponentType<MermaidErrorComponentProps>;
}
type StreamdownProps = Options & {
    mode?: "static" | "streaming";
    BlockComponent?: React.ComponentType<BlockProps>;
    parseMarkdownIntoBlocksFn?: (markdown: string) => string[];
    parseIncompleteMarkdown?: boolean;
    className?: string;
    shikiTheme?: [BundledTheme, BundledTheme];
    mermaid?: MermaidOptions;
    controls?: ControlsConfig;
    isAnimating?: boolean;
    caret?: keyof typeof carets;
    plugins?: PluginConfig;
    remend?: RemendOptions;
    linkSafety?: LinkSafetyConfig;
};
declare const defaultRehypePlugins: Record<string, Pluggable>;
declare const defaultRemarkPlugins: Record<string, Pluggable>;
declare const carets: {
    block: string;
    circle: string;
};
interface StreamdownContextType {
    shikiTheme: [BundledTheme, BundledTheme];
    controls: ControlsConfig;
    isAnimating: boolean;
    mode: "static" | "streaming";
    mermaid?: MermaidOptions;
    linkSafety?: LinkSafetyConfig;
}
declare const StreamdownContext: react.Context<StreamdownContextType>;
type BlockProps = Options & {
    content: string;
    shouldParseIncompleteMarkdown: boolean;
    index: number;
};
declare const Block: react.MemoExoticComponent<({ content, shouldParseIncompleteMarkdown: _, index: __, ...props }: BlockProps) => react_jsx_runtime.JSX.Element>;
declare const Streamdown: react.MemoExoticComponent<({ children, mode, parseIncompleteMarkdown: shouldParseIncompleteMarkdown, components, rehypePlugins, remarkPlugins, className, shikiTheme, mermaid, controls, isAnimating, BlockComponent, parseMarkdownIntoBlocksFn, caret, plugins, remend: remendOptions, linkSafety, ...props }: StreamdownProps) => react_jsx_runtime.JSX.Element>;

export { Block, type CjkPlugin, type CodeHighlighterPlugin, type ControlsConfig, type DiagramPlugin, type HighlightOptions, type LinkSafetyConfig, type LinkSafetyModalProps, type MathPlugin, type MermaidErrorComponentProps, type MermaidOptions, type PluginConfig, Streamdown, StreamdownContext, type StreamdownContextType, type StreamdownProps, defaultRehypePlugins, defaultRemarkPlugins, parseMarkdownIntoBlocks };
