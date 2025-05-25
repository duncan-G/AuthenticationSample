"use client"

import type React from "react"

import { useState, useEffect, useRef } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card } from "@/components/ui/card"
import {GreeterClient} from "@/app/services/greet/GreetServiceClientPb";
import {HelloRequest} from "@/app/services/greet/greet_pb";
import { ThemeToggle } from "@/components/theme/theme-toggle"

interface Message {
  id: string
  text: string
  createdAt: number
  scheduledDisappearAt: number
  isExiting: boolean
}

export default function Component() {
  const [messages, setMessages] = useState<Message[]>([])
  const [inputValue, setInputValue] = useState("")
  const [error, setError] = useState('');
  const timersRef = useRef<Map<string, NodeJS.Timeout>>(new Map())
  const client = new GreeterClient('https://localhost:10000');

  const removeMessage = (messageId: string) => {
    // Clear timer for this message
    const timer = timersRef.current.get(messageId)
    if (timer) {
      clearTimeout(timer)
      timersRef.current.delete(messageId)
    }

    // Start exit animation
    setMessages((prev) => prev.map((msg) => (msg.id === messageId ? { ...msg, isExiting: true } : msg)))

    // Remove message after animation
    setTimeout(() => {
      setMessages((prev) => prev.filter((msg) => msg.id !== messageId))
    }, 500)
  }

  const addMessage = (text: string) => {
    const now = Date.now()
    const creationTime = now

    // Find the latest scheduled disappearance time from previous messages
    const latestPreviousDisappearance = Math.max(0, messages.at(0)?.scheduledDisappearAt ?? 0)

    // Calculate when this message should disappear
    // max(5s from creation, 1s after latest previous disappearance)
    const naturalDisappearTime = creationTime + 5000
    const chainDisappearTime = latestPreviousDisappearance + 1000
    const scheduledDisappearAt = Math.max(naturalDisappearTime, chainDisappearTime)

    const newMessage: Message = {
      id: now.toString(),
      text: text.trim(),
      createdAt: creationTime,
      scheduledDisappearAt,
      isExiting: false,
    }

    setMessages((prev) => [newMessage, ...prev])

    // Set timer for this message
    const delay = scheduledDisappearAt - now - 500 // Subtract 500ms for exit animation
    const timer = setTimeout(() => {
      removeMessage(newMessage.id)
    }, delay)

    timersRef.current.set(newMessage.id, timer)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!inputValue) return

    const request = new HelloRequest();
    request.setName(inputValue);

    try
    {
      const response = await client.sayHello(request, {});
      addMessage(response.getMessage());
      setInputValue("")
      setError("") // Clear any previous errors
    } catch (err) {
      setError('Error calling service: ' + (err instanceof Error ? err.message : String(err)));
    }
  }

  // Clean up timers on unmount
  useEffect(() => {
    return () => {
      timersRef.current.forEach((timer) => clearTimeout(timer))
      timersRef.current.clear()
    }
  }, [])

  return (
    <div className="w-full max-w-md mx-auto p-6 space-y-6 min-h-screen">
      <Card className="p-6 border-border bg-card">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-2xl font-bold text-card-foreground">Greeter Example</h2>
          <ThemeToggle />
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Input
              type="text"
              placeholder="Enter your name..."
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              className="w-full bg-background border-input text-foreground placeholder:text-muted-foreground"
            />
          </div>
          <Button type="submit" className="w-full">
            Send Greeting
          </Button>
        </form>

        {error && (
          <div className="mt-4 p-3 bg-destructive/10 border border-destructive/20 rounded-md">
            <p className="text-sm text-destructive">{error}</p>
          </div>
        )}

        {messages.length > 0 && (
          <div className="mt-4 text-center">
            <p className="text-xs text-muted-foreground">
              {messages.length} active message{messages.length !== 1 ? "s" : ""}
            </p>
          </div>
        )}
      </Card>

      <div className="space-y-3">
        {messages.map((message) => (
          <MessageItem key={message.id} message={message} />
        ))}
      </div>
    </div>
  )
}

function MessageItem({ message }: { message: Message }) {
  const [timeLeft, setTimeLeft] = useState(0)
  const [isExtended, setIsExtended] = useState(false)

  useEffect(() => {
    // Check if this message was extended beyond the natural 5s
    const naturalDisappearTime = message.createdAt + 5000
    setIsExtended(message.scheduledDisappearAt > naturalDisappearTime)

    const interval = setInterval(() => {
      const now = Date.now()
      const remaining = Math.max(0, (message.scheduledDisappearAt - now) / 1000)
      setTimeLeft(remaining)

      if (remaining <= 0) {
        clearInterval(interval)
      }
    }, 100)

    return () => clearInterval(interval)
  }, [message.scheduledDisappearAt, message.createdAt])

  const totalDuration = (message.scheduledDisappearAt - message.createdAt) / 1000
  const progress = Math.max(0, Math.min(1, timeLeft / totalDuration))

  return (
      <div
          className={`
        p-4 bg-card border rounded-lg shadow-sm
        transition-all duration-500 ease-in-out
        ${
          message.isExiting
            ? "transform translate-y-full opacity-0"
            : "transform translate-y-0 opacity-100 animate-slide-in-from-top"
          }
        ${isExtended ? "border-purple-500 dark:border-purple-400" : "border-border"}
      `}
      >
        <p className="text-card-foreground">{message.text}</p>
        <div className="flex justify-between items-center mt-2">
          <p className="text-xs text-muted-foreground">
            {isExtended ? (
                <>
                  Queued: {timeLeft.toFixed(1)}s
                  <span className="text-purple-600 dark:text-purple-400 ml-1">(extended)</span>
                </>
            ) : (
                <>Disappears in {timeLeft.toFixed(1)}s</>
            )}
          </p>
          <div className="w-16 bg-muted rounded-full h-1">
            <div
                className={`h-1 rounded-full transition-all duration-100 ${
                    isExtended ? "bg-purple-500 dark:bg-purple-400" : "bg-primary"
                }`}
                style={{ width: `${progress * 100}%` }}
            />
          </div>
        </div>
      </div>
  )
}
