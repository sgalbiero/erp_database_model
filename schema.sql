-- START OF THE PRODUCTS LOGIC (Usage queries in the README.md) --
-- Products base
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    cost NUMERIC(10,2),
    price NUMERIC(10,2),
    main_sku VARCHAR(50) UNIQUE NOT NULL,
    category_id INT REFERENCES categories(id)
);

-- Categories base
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

-- Variation types (Examples: Color, Size, Voltage)
CREATE TABLE variation_types (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);

-- Variation Values (Examples: Black, White, 40, 41...)
CREATE TABLE variation_values (
    id SERIAL PRIMARY KEY,
    variation_type_id INT REFERENCES variation_types(id),
    value VARCHAR(50) NOT NULL
);

-- Product Variations (Actual SKU level)
CREATE TABLE product_variations (
    id SERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id),
    sku VARCHAR(100) UNIQUE,
    stock INT DEFAULT 0
);

-- Variation Items (bridge table)
CREATE TABLE product_variation_items (
    id SERIAL PRIMARY KEY,
    variation_id INT REFERENCES product_variations(id),
    variation_value_id INT REFERENCES variation_values(id)
);

-- Automatic Trigger for SKU generation
CREATE OR REPLACE FUNCTION update_variation_sku()
RETURNS TRIGGER AS $$
DECLARE
    base_sku TEXT;
    suffix TEXT;
BEGIN
    -- get main SKU
    SELECT p.main_sku
    INTO base_sku
    FROM products p
    JOIN product_variations pv ON pv.product_id = p.id
    WHERE pv.id = NEW.variation_id;

    -- build suffix (color, size, etc.)
    SELECT string_agg(v.value, '-' ORDER BY vt.name)
    INTO suffix
    FROM product_variation_items pvi
    JOIN variation_values v ON v.id = pvi.variation_value_id
    JOIN variation_types vt ON vt.id = v.variation_type_id
    WHERE pvi.variation_id = NEW.variation_id;

    -- update SKU
    UPDATE product_variations
    SET sku = base_sku || '-' || suffix
    WHERE id = NEW.variation_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_variation_sku
AFTER INSERT ON product_variation_items
FOR EACH ROW
EXECUTE FUNCTION update_variation_sku();

-- END OF THE PRODUCTS LOGIC --
