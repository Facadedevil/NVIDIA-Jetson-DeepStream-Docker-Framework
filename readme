# Replace the current update-readme job with this:

  update-readme:
    needs: build
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/'))
    permissions:
      packages: write
      contents: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Update container description
        env:
          REPO: ${{ github.repository }}
          IMAGE_NAME: ${{ env.IMAGE_NAME || github.repository }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # Extract repository information
          OWNER=$(echo "$REPO" | cut -d '/' -f 1)
          NAME=$(echo "$REPO" | cut -d '/' -f 2)
          IMAGE_NAME_LOWER=$(echo "$IMAGE_NAME" | tr '[:upper:]' '[:lower:]')
          
          echo "Updating description for ghcr.io/$IMAGE_NAME_LOWER"
          
          # Get README content
          README_CONTENT=$(cat README.md)
          
          # Use GitHub API to update package description
          PACKAGE_ID=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
            "https://api.github.com/orgs/$OWNER/packages/container/$NAME/versions" | \
            jq -r '.[] | select(.metadata.container.tags[] | contains("latest")) | .id' | head -n 1)
          
          if [ -n "$PACKAGE_ID" ]; then
            echo "Found package ID: $PACKAGE_ID"
            
            # Update package description
            curl -X PATCH \
              -H "Authorization: Bearer $GH_TOKEN" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/user/packages/container/$NAME" \
              -d "{\"description\":\"Universal Docker framework for NVIDIA Jetson devices with automatic hardware detection\"}"
            
            echo "Successfully updated package description"
          else
            echo "Could not find package ID. Make sure the package exists and you have proper permissions."
            echo "This is non-fatal, continuing workflow."
          fi
