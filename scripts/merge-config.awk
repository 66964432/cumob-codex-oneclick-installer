BEGIN {
  in_managed = 0
  section = ""
  skip_section = 0
}

{
  line = $0

  if (line == "# BEGIN CUMOB CODEX ONE-CLICK INSTALLER") {
    in_managed = 1
    next
  }

  if (in_managed) {
    if (line == "# END CUMOB CODEX ONE-CLICK INSTALLER") {
      in_managed = 0
      section = ""
      skip_section = 0
    }
    next
  }

  if (line ~ /^[[:space:]]*\[[^][]+\][[:space:]]*(#.*)?$/) {
    header = line
    sub(/^[[:space:]]*\[/, "", header)
    sub(/\][[:space:]]*(#.*)?$/, "", header)
    gsub(/[[:space:]]/, "", header)
    section = tolower(header)
    skip_section = 0
    if (section == "model_providers.cumob") {
      skip_section = 1
    }
    if (section == "model_providers.\"cumob\"") {
      skip_section = 1
    }
    if (section == "model_providers.'cumob'") {
      skip_section = 1
    }

    if (skip_section) {
      next
    }
  }

  if (skip_section) {
    next
  }

  if (section == "") {
    if (line ~ /^[[:space:]]*(model_provider|model|disable_response_storage|model_catalog_json|model_reasoning_effort)[[:space:]]*=/) {
      next
    }
  }

  print line
}
