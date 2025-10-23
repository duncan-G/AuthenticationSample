'use client'

import { AuthProvider } from 'react-oidc-context'
import React from 'react'
import { config } from '@/lib/config'
import type { UserManagerSettings } from 'oidc-client-ts'

type OidcProviderProps = {
  children: React.ReactNode
}

export default function OidcProvider({ children }: OidcProviderProps) {
  const { authority, clientId, redirectUri, scope, responseType } = config

  const cognitoAuthConfig: UserManagerSettings = {
    authority,
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: responseType,
    scope,
  }

  const onSigninCallback = () => {
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href)
      url.search = ''
      url.hash = ''
      window.history.replaceState({}, document.title, url.toString())
    }
  }

  return (
    <AuthProvider {...cognitoAuthConfig} onSigninCallback={onSigninCallback}>
      {children}
    </AuthProvider>
  )
}


