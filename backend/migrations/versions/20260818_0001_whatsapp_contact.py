import sqlalchemy as sa
from alembic import op

revision = "20260818_0001"
down_revision = "20260816_0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users", sa.Column("whatsapp_phone", sa.String(length=32), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("users", "whatsapp_phone")
