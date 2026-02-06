import * as React from "react"
import { cn } from '@/lib/utils'

const Button = React.forwardRef(({ className, variant = 'default', size = 'default', ...props }, ref) => (
  <button
    ref={ref}
    type={props.type ?? "button"}
    className={cn(
      'inline-flex items-center justify-center rounded-md font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50',
      variant === 'default' && 'bg-primary text-primary-foreground hover:bg-primary/90',
      variant === 'ghost' && 'hover:bg-accent hover:text-accent-foreground',
      variant === 'outline' && 'border border-input bg-background hover:bg-accent hover:text-accent-foreground',
      size === 'default' && 'h-9 px-4 py-2',
      size === 'sm' && 'h-8 rounded-md px-3 text-sm',
      size === 'icon' && 'h-9 w-9',
      size === 'icon-sm' && 'h-8 w-8',
      className
    )}
    {...props}
  />
))
Button.displayName = "Button"

export { Button }
