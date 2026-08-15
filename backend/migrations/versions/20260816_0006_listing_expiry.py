from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260816_0006"
down_revision: str | None = "20260813_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "listings",
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.execute(
        sa.text(
            "UPDATE listings "
            "SET expires_at = created_at + interval '30 days' "
            "WHERE expires_at IS NULL"
        )
    )
    op.alter_column(
        "listings",
        "expires_at",
        nullable=False,
        server_default=sa.text("now() + interval '30 days'"),
    )
    op.create_index(
        "ix_listings_status_expires",
        "listings",
        ["status", "expires_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_listings_status_expires", table_name="listings")
    op.drop_column("listings", "expires_at")
