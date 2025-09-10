import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import ThemeInitializer from "@/components/theme/theme-initializer";
import { ThemeProvider } from "@/components/theme/theme-provider";
import OidcProvider from "@/components/auth/oidc-provider";
import { WorkflowProvider } from "@/lib/workflows";
import { getTraceparentFromActiveSpan } from "@/lib/server/trace";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Authentication Sample",
  description: "Authentication with AWS Cognito",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Server component: compute traceparent for initial HTML load if there is an active server span
  const traceparent = getTraceparentFromActiveSpan();
  return (
    <html lang="en">
      <head>
        {traceparent ? (
          <meta name="traceparent" content={traceparent} />
        ) : null}
      </head>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased bg-background text-foreground`} suppressHydrationWarning={true}
      >
      <ThemeInitializer />
      <WorkflowProvider>
        <OidcProvider>
          <ThemeProvider>{children}</ThemeProvider>
        </OidcProvider>
      </WorkflowProvider>
      </body>
    </html>
  );
}
