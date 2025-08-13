"use client"

export default function ThemeInitializer() {
  function script() {
    const savedTheme = localStorage.getItem("theme")
    const prefersDark = savedTheme ? savedTheme === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches

    if (prefersDark) {
      document.body.classList.add("dark")
    } else {
      document.body.classList.remove("dark")
    }
  }

  return <script suppressHydrationWarning dangerouslySetInnerHTML={{ __html: `(${script.toString()})()` }} />
}
