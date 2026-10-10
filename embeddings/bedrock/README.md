# Amazon Bedrock embeddings

`bedrock.Client` invokes Titan Text Embeddings V1/V2 or Cohere Embed V3 through
the Bedrock Runtime `InvokeModel` API. Authentication uses an injected Amazon
Bedrock API key (`Authorization: Bearer ...`) and never discovers credentials
implicitly. Titan requests embed one text at a time; Cohere requests batch up
to 96 texts and distinguish `search_document` from `search_query` inputs.

The V2 Titan client supports 256, 512, or 1,024 dimensions and normalization.
Requests are limited to 1 MiB and responses to 16 MiB. All returned vectors
must be finite, non-empty, and dimensionally consistent. Custom base URLs must
use HTTPS. This client currently supports Bedrock API keys; AWS credential-chain
and SigV4 signing are not implemented.
