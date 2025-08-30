"use client"

import Link from "next/link"

export default function LogoutCompletePage() {
  return (
    <div className="p-6">
      <h1 className="text-xl font-semibold mb-2">You have been signed out.</h1>
      <p>Return to the <Link className="underline" href="/">home page</Link>.</p>
    </div>
  )
}


