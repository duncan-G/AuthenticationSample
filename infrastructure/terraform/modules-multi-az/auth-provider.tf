# =============================================================================
# Cognito Social Identity Providers (Optional)
# =============================================================================

locals {
  idp_pairs = {
    for pair in setproduct(keys(var.idps), local.auth_environments) : "${pair[0]}-${pair[1]}" => {
      idp_key = pair[0]
      env     = pair[1]
    }
  }
}

resource "aws_cognito_identity_provider" "social" {
  for_each = local.idp_pairs

  user_pool_id  = aws_cognito_user_pool.this[each.value.env].id
  provider_name = var.idps[each.value.idp_key].provider_name
  provider_type = var.idps[each.value.idp_key].provider_type

  provider_details = {
    client_id        = var.idps[each.value.idp_key].client_id
    client_secret    = var.idps[each.value.idp_key].client_secret
    authorize_scopes = var.idps[each.value.idp_key].scopes
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}


