from alembic import op

revision = "20260816_0007"
down_revision = "20260816_0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint(
        op.f("ck_listings_title_length_allowed"), "listings", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_listings_title_length_allowed"),
        "listings",
        "char_length(title) BETWEEN 1 AND 80",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_listings_title_length_allowed"), "listings", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_listings_title_length_allowed"),
        "listings",
        "char_length(title) BETWEEN 3 AND 80",
    )
