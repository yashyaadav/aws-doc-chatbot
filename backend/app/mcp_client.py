"""Factory for the awslabs AWS Documentation MCP server.

The server is a stdio MCP server installed into the image at build time
(console script: ``awslabs.aws-documentation-mcp-server``). We connect to it
over stdio and let Strands expose its tools (search/read/recommend docs) to the
agent. The server fetches from docs.aws.amazon.com, so the host needs egress.
"""

import os
import sys

from mcp import StdioServerParameters, stdio_client
from strands.tools.mcp import MCPClient

# Launch the server module with the current interpreter (PATH-independent — works
# the same in the local venv and the Lambda image) rather than the console script.
_SERVER_MODULE = "awslabs.aws_documentation_mcp_server.server"


def build_aws_docs_mcp_client() -> MCPClient:
    """Return a Strands MCPClient bound to the AWS Documentation MCP server.

    Use it as a context manager; tools are only callable while the context is
    open. We keep one client open for the lifetime of the app process.
    """
    return MCPClient(
        lambda: stdio_client(
            StdioServerParameters(
                command=sys.executable,
                args=["-m", _SERVER_MODULE],
                env={**os.environ, "FASTMCP_LOG_LEVEL": "ERROR"},
            )
        )
    )
