package cl.duoc.mi_foro_usuarios.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import cl.duoc.mi_foro_usuarios.entity.UsuarioEntity;


@Repository 
public interface UsuarioRepository extends JpaRepository<UsuarioEntity, Long> {

    Optional<UsuarioEntity> findByUsuario(String usuario);

    boolean existsByUsuario(String usuario);

}
