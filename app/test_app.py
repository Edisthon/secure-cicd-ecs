import pytest
from app import app


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


def test_home(client):
    response = client.get('/')
    assert response.status_code == 200
    assert response.json == {"message": "Welcome to the E-Commerce API!"}


def test_health(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert response.json == {"status": "healthy"}


def test_version(client):
    response = client.get('/version')
    assert response.status_code == 200
    assert "version" in response.json


def test_checkout(client):
    # Randomly returns 200 or 500 by design; we only assert it answers with JSON.
    response = client.get('/checkout')
    assert response.status_code in [200, 500]
    assert response.is_json


def test_get_item_success(client):
    response = client.get('/item/1')
    assert response.status_code == 200
    assert "Laptop" in response.json['item']['name']


def test_get_item_not_found(client):
    response = client.get('/item/999')
    assert response.status_code == 404
    assert response.json == {"error": "Item not found"}


def test_add_to_cart_success(client):
    response = client.post('/cart', json={"item_id": "2"})
    assert response.status_code == 201


def test_add_to_cart_bad_request(client):
    response = client.post('/cart', json={})
    assert response.status_code == 400


def test_add_to_cart_not_found(client):
    response = client.post('/cart', json={"item_id": "999"})
    assert response.status_code == 404


def test_metrics_exposed(client):
    client.get('/health')
    response = client.get('/metrics')
    assert response.status_code == 200
    assert b"http_requests_total" in response.data
